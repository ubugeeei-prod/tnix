{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Testable JSON-RPC/LSP helpers for tnix.
module Server (
  ReadOutcome (..),
  applyContentChanges,
  asInt,
  asText,
  clearDiagnostics,
  clientCapabilities,
  completionResult,
  contentLengthFromHeaders,
  contentChanges,
  diag,
  documentPath,
  field,
  findDefinitionRange,
  findFieldRange,
  findWordRange,
  firstChange,
  hoverResult,
  location,
  notify,
  pathUri,
  publishDiagnostics,
  publishDiagnosticsWithContent,
  readMessage,
  readMessageOutcome,
  respond,
  send,
  textOffsetToUtf16Column,
  textRangeToUtf16Columns,
  uriPath,
  wordAt,
)
where

import Control.Applicative ((<|>))
import Control.Monad (foldM)
import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Foldable (toList)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read qualified as TextRead
import Driver (Analysis (..), lookupSymbolType)
import Pretty (renderScheme)
import ServerProtocol
  ( ReadOutcome (..),
    contentLengthFromHeaders,
    notify,
    readMessage,
    readMessageOutcome,
    send,
  )
import ServerUri (pathUri, uriPath)
import Subtyping (lookupRecordField, resolveType)
import System.IO (Handle)
import Type (Multiplicity (..), Name, Scheme (..), Type (..), TypeAlias, schemeFromAnnotation, tDynamic, tPath)

field :: Text -> Value -> Maybe Value
field key (Object obj) = KeyMap.lookup (Key.fromText key) obj
field _ _ = Nothing

asText :: Value -> Maybe Text
asText (String text) = Just text
asText _ = Nothing

asInt :: Value -> Int
asInt (Number n) = floor n
asInt _ = 0

clientCapabilities :: Value
clientCapabilities =
  object
    [ "capabilities"
        .= object
          [ "hoverProvider" .= True
          , "completionProvider" .= object ["triggerCharacters" .= ["." :: Text]]
          , "definitionProvider" .= True
          , "declarationProvider" .= True
          , "referencesProvider" .= True
          , "renameProvider" .= True
          , "documentSymbolProvider" .= True
          , "workspaceSymbolProvider" .= True
          , "codeActionProvider" .= True
          , "inlayHintProvider" .= object ["resolveProvider" .= False]
          , "semanticTokensProvider"
              .= object
                [ "legend"
                    .= object
                      [ "tokenTypes"
                          .= [ "keyword" :: Text
                             , "type"
                             , "function"
                             , "variable"
                             , "property"
                             , "string"
                             , "number"
                             , "operator"
                             ]
                      , "tokenModifiers" .= ([] :: [Text])
                      ]
                , "full" .= True
                ]
          , "textDocumentSync"
              .= object
                [ "openClose" .= True
                , "change" .= (2 :: Int)
                , "save" .= object ["includeText" .= True]
                ]
          ]
    ]

firstChange :: Maybe Value -> Maybe Value
firstChange params = do
  Array changes <- field "contentChanges" =<< params
  listToMaybe (toList changes)

contentChanges :: Maybe Value -> [Value]
contentChanges params =
  case field "contentChanges" =<< params of
    Just (Array changes) -> toList changes
    _ -> []

applyContentChanges :: Text -> Maybe Value -> Either String Text
applyContentChanges initial params =
  foldl' (\acc change -> acc >>= (`applyContentChange` change)) (Right initial) (contentChanges params)

applyContentChange :: Text -> Value -> Either String Text
applyContentChange content change = do
  replacement <- maybe (Left "content change is missing text") Right (field "text" change >>= asText)
  case field "range" change of
    Nothing -> Right replacement
    Just range -> do
      start <- rangePos "start" range >>= positionOffset content
      end <- rangePos "end" range >>= positionOffset content
      if start > end
        then Left "content change range is inverted"
        else Right (T.take start content <> replacement <> T.drop end content)
 where
  rangePos :: Text -> Value -> Either String (Int, Int)
  rangePos key range = do
    pos <- maybe (Left ("content change range is missing " <> T.unpack key)) Right (field key range)
    lineNo <- maybe (Left ("content change range is missing " <> T.unpack key <> ".line")) Right (field "line" pos)
    charNo <- maybe (Left ("content change range is missing " <> T.unpack key <> ".character")) Right (field "character" pos)
    Right (asInt lineNo, asInt charNo)

positionOffset :: Text -> (Int, Int) -> Either String Int
positionOffset content (lineNo, charNo)
  | lineNo < 0 = Left "content change line is out of bounds"
  | charNo < 0 = Left "content change character is out of bounds"
  | otherwise =
      go 0 lineNo (T.splitOn "\n" content)
 where
  go offset 0 (line : _) =
    case utf16ColumnToTextOffset line charNo of
      Just lineOffset -> Right (offset + lineOffset)
      Nothing -> Left "content change character is out of bounds"
  go offset n (line : rest) =
    go (offset + T.length line + 1) (n - 1) rest
  go _ _ [] = Left "content change line is out of bounds"

utf16ColumnToTextOffset :: Text -> Int -> Maybe Int
utf16ColumnToTextOffset line target
  | target < 0 = Nothing
  | otherwise = go 0 0 (T.unpack line)
 where
  go textOffset utf16Offset [] =
    if target == utf16Offset then Just textOffset else Nothing
  go textOffset utf16Offset (char : rest)
    | target == utf16Offset = Just textOffset
    | target < nextUtf16Offset = Nothing
    | otherwise = go (textOffset + 1) nextUtf16Offset rest
   where
    nextUtf16Offset = utf16Offset + utf16CharWidth char

textOffsetToUtf16Column :: Text -> Int -> Int
textOffsetToUtf16Column line offset =
  T.foldl' (\column char -> column + utf16CharWidth char) 0 (T.take offset line)

textRangeToUtf16Columns :: Text -> Int -> Int -> (Int, Int)
textRangeToUtf16Columns line startOffset endOffset =
  (textOffsetToUtf16Column line startOffset, textOffsetToUtf16Column line endOffset)

utf16CharWidth :: Char -> Int
utf16CharWidth char
  | fromEnum char > 0xffff = 2
  | otherwise = 1

diag :: String -> Value
diag err = object ["range" .= object ["start" .= pos, "end" .= pos], "severity" .= (1 :: Int), "message" .= err]
 where
  pos = object ["line" .= (0 :: Int), "character" .= (0 :: Int)]

location :: FilePath -> Int -> Int -> Int -> Value
location file lineNo startChar endChar =
  object
    [ "uri" .= pathUri file
    , "range"
        .= object
          [ "start" .= object ["line" .= lineNo, "character" .= startChar]
          , "end" .= object ["line" .= lineNo, "character" .= endChar]
          ]
    ]

publishDiagnostics :: FilePath -> Either String Analysis -> Value
publishDiagnostics file result =
  object
    [ "uri" .= pathUri file
    , "diagnostics"
        .= either
          (\err -> [diag err])
          (const ([] :: [Value]))
          result
    ]

publishDiagnosticsWithContent :: FilePath -> Text -> Either String Analysis -> Value
publishDiagnosticsWithContent file content result =
  object
    [ "uri" .= pathUri file
    , "diagnostics"
        .= either
          (\err -> [diagnosticWithContent content err])
          (const ([] :: [Value]))
          result
    ]

completionResult :: Either String Analysis -> Text -> Int -> Int -> Value
completionResult result content lineNo charNo =
  object
    [ "isIncomplete" .= False
    , "items"
        .= case result of
          Left _ -> ([] :: [Value])
          Right analysis -> map completionItem (completionCandidates analysis content lineNo charNo)
    ]

hoverResult :: Either String Analysis -> Text -> Int -> Int -> Value
hoverResult result content lineNo charNo =
  object
    [ "contents"
        .= object
          [ "kind" .= ("markdown" :: Text)
          , "value" .= ("```tnix\n" <> rendered <> "\n```" :: Text)
          ]
    ]
 where
  rendered =
    case result of
      Left err -> T.pack err
      Right analysis ->
        maybe
          (maybe "No type information." renderScheme (analysisRoot analysis))
          renderScheme
          (hoveredSchemeAt analysis lineNo charNo content)

hoveredSchemeAt :: Analysis -> Int -> Int -> Text -> Maybe Scheme
hoveredSchemeAt analysis lineNo charNo content =
  case hoveredPathAt lineNo charNo content of
    [] -> analysisRoot analysis
    [name] -> resolveSymbol analysis name
    path -> schemeFromAnnotation <$> resolveChainType analysis path

hoveredPathAt :: Int -> Int -> Text -> [Text]
hoveredPathAt lineNo charNo content =
  case drop lineNo (T.lines content) of
    line : _ ->
      case utf16ColumnToTextOffset line charNo of
        Just charOffset ->
          let (beforeCursor, afterCursor) = T.splitAt charOffset line
              prefix = T.reverse (T.takeWhile completionChar (T.reverse beforeCursor))
              suffix = T.takeWhile completionChar afterCursor
              fragment = prefix <> suffix
              parts = filter (not . T.null) (T.splitOn "." fragment)
              segmentCount = min (length parts) (T.count "." prefix + 1)
           in take segmentCount parts
        Nothing -> []
    _ -> []

diagnosticWithContent :: Text -> String -> Value
diagnosticWithContent content err =
  case diagnosticRange content (T.pack err) of
    Just (lineNo, startChar, endChar) ->
      object
        [ "range"
            .= object
              [ "start" .= object ["line" .= lineNo, "character" .= startChar]
              , "end" .= object ["line" .= lineNo, "character" .= endChar]
              ]
        , "severity" .= (1 :: Int)
        , "message" .= err
        ]
    Nothing -> diag err

diagnosticRange :: Text -> Text -> Maybe (Int, Int, Int)
diagnosticRange content err =
  parserRange content err
    <|> semanticRange content err

parserRange :: Text -> Text -> Maybe (Int, Int, Int)
parserRange content err = do
  firstLine <- listToMaybe (T.lines err)
  let numbers = mapMaybe parseDecimal (reverse (T.splitOn ":" firstLine))
  case numbers of
    colNo : lineNo : _ ->
      let lineIx = max 0 (lineNo - 1)
          charIx = max 0 (colNo - 1)
       in Just $
            case drop lineIx (T.lines content) of
              line : _ ->
                let endIx = charIx + tokenWidthAt content lineIx charIx
                    (startChar, endChar) = textRangeToUtf16Columns line charIx endIx
                 in (lineIx, startChar, endChar)
              [] -> (lineIx, charIx, charIx + 1)
    _ -> Nothing
 where
  parseDecimal chunk =
    case TextRead.decimal chunk of
      Right (n, "") -> Just n
      _ -> Nothing

semanticRange :: Text -> Text -> Maybe (Int, Int, Int)
semanticRange content err = do
  needle <- firstQuoted err
  if "missing field" `T.isPrefixOf` err
    then findFieldRange content needle <|> findWordRange content needle
    else
      if any (`T.isPrefixOf` err) ["duplicate bindings", "duplicate signatures", "missing bindings for signatures"]
        then findDefinitionRange content needle <|> findWordRange content needle
        else findWordRange content needle

firstQuoted :: Text -> Maybe Text
firstQuoted text = do
  (_, suffix) <- guardBreak (T.breakOn "\"" text)
  let rest = T.drop 1 suffix
      (quoted, trailing) = T.breakOn "\"" rest
  if T.null trailing then Nothing else Just quoted
 where
  guardBreak pair@(_, suffix)
    | T.null suffix = Nothing
    | otherwise = Just pair

completionCandidates :: Analysis -> Text -> Int -> Int -> [(Text, Scheme)]
completionCandidates analysis content lineNo charNo =
  case completionContext lineNo charNo content of
    ([], prefix) -> filterByPrefix prefix (topLevelCandidates analysis)
    (path, prefix) ->
      case resolveChainType analysis path of
        Just ty -> filterByPrefix prefix (recordFieldCandidates (analysisAliases analysis) ty)
        Nothing -> []

completionContext :: Int -> Int -> Text -> ([Text], Text)
completionContext lineNo charNo content =
  let fragment = completionFragment lineNo charNo content
      parts = T.splitOn "." fragment
   in case reverse parts of
        [] -> ([], "")
        partial : revPath -> (filter (not . T.null) (reverse revPath), partial)

completionFragment :: Int -> Int -> Text -> Text
completionFragment lineNo charNo content =
  case drop lineNo (T.lines content) of
    line : _ ->
      case utf16ColumnToTextOffset line charNo of
        Just charOffset -> T.takeWhileEnd completionChar (T.take charOffset line)
        Nothing -> ""
    _ -> ""

completionChar :: Char -> Bool
completionChar char = wordChar char || char == '.'

wordChar :: Char -> Bool
wordChar char =
  char == '_'
    || char == '-'
    || char == '\''
    || char == '?'
    || char == '!'
    || char `elem` ['0' .. '9']
    || char `elem` ['A' .. 'Z']
    || char `elem` ['a' .. 'z']

topLevelCandidates :: Analysis -> [(Text, Scheme)]
topLevelCandidates analysis =
  sortOn fst . dedupeByLabel $
    builtinsCandidate
      <> rootFieldCandidates
      <> defaultCandidate
      <> importCandidate
      <> Map.toList (analysisBindings analysis)
 where
  builtinsCandidate = maybe [] (\scheme -> [("builtins", scheme)]) (Map.lookup "builtins" (analysisAmbient analysis))
  rootFieldCandidates =
    case analysisRoot analysis of
      Just scheme ->
        case resolveType (analysisAliases analysis) (schemeType scheme) of
          TRecord fields ->
            [ (name, schemeFromAnnotation fieldTy)
            | (name, fieldTy) <- Map.toList fields
            ]
          _ -> []
      Nothing -> []
  defaultCandidate = maybe [] (\scheme -> [("default", scheme)]) (analysisRoot analysis)
  importCandidate = [("import", Scheme [] (TFun Many tPath tDynamic))]

recordFieldCandidates :: Map.Map Name TypeAlias -> Type -> [(Text, Scheme)]
recordFieldCandidates aliases ty =
  sortOn fst $
    [ (name, schemeFromAnnotation fieldTy)
    | (name, fieldTy) <- accessibleFields aliases ty
    ]

accessibleFields :: Map.Map Name TypeAlias -> Type -> [(Text, Type)]
accessibleFields aliases ty =
  case resolveType aliases ty of
    TRecord fields -> Map.toList fields
    TUnion members ->
      let names = nub (concatMap (map fst . accessibleFields aliases) members)
       in mapMaybe (\name -> fmap (\fieldTy -> (name, fieldTy)) (lookupRecordField aliases ty name)) names
    _ -> []

resolveChainType :: Analysis -> [Text] -> Maybe Type
resolveChainType analysis = \case
  [] -> schemeType <$> analysisRoot analysis
  headName : rest -> do
    scheme <- resolveSymbol analysis headName
    foldM (lookupRecordField (analysisAliases analysis)) (schemeType scheme) rest

resolveSymbol :: Analysis -> Text -> Maybe Scheme
resolveSymbol analysis name
  | name == "builtins" = Map.lookup "builtins" (analysisAmbient analysis)
  | name == "import" = Just (Scheme [] (TFun Many tPath tDynamic))
  | otherwise = lookupSymbolType analysis name

filterByPrefix :: Text -> [(Text, Scheme)] -> [(Text, Scheme)]
filterByPrefix prefix = filter (\(label, _) -> T.null prefix || prefix `T.isPrefixOf` label)

dedupeByLabel :: [(Text, Scheme)] -> [(Text, Scheme)]
dedupeByLabel =
  Map.toList . Map.fromListWith (\left _ -> left)

completionItem :: (Text, Scheme) -> Value
completionItem (label, scheme) =
  object
    [ "label" .= label
    , "kind" .= completionKind (schemeType scheme)
    , "detail" .= renderScheme scheme
    ]
 where
  completionKind ty =
    case ty of
      TFun{} -> (3 :: Int)
      _ -> (6 :: Int)

findDefinitionRange :: Text -> Text -> Maybe (Int, Int, Int)
findDefinitionRange content symbol =
  listToMaybe $
    mapMaybe
      ( \(lineNo, line) ->
          fmap
            ( \(startOffset, endOffset) ->
                let (startChar, endChar) = textRangeToUtf16Columns line startOffset endOffset
                 in (lineNo, startChar, endChar)
            )
            (definitionSpan line symbol)
      )
      (zip [0 ..] (T.lines content))

definitionSpan :: Text -> Text -> Maybe (Int, Int)
definitionSpan line symbol =
  let stripped = T.stripStart line
      indent = T.length line - T.length stripped
      candidates =
        [ "type " <> symbol
        , symbol <> "::"
        , symbol <> " ::"
        , symbol <> "="
        , symbol <> " ="
        ]
   in listToMaybe
        [ (indent + startChar, indent + startChar + T.length symbol)
        | candidate <- candidates
        , let (prefix, suffix) = T.breakOn candidate stripped
        , not (T.null suffix)
        , let startChar = T.length prefix + if "type " `T.isPrefixOf` candidate then 5 else 0
        ]

findFieldRange :: Text -> Text -> Maybe (Int, Int, Int)
findFieldRange content symbol =
  listToMaybe $
    mapMaybe
      ( \(lineNo, line) ->
          fmap
            ( \startOffset ->
                let (startChar, endChar) = textRangeToUtf16Columns line startOffset (startOffset + T.length symbol)
                 in (lineNo, startChar, endChar)
            )
            (fieldSpan line symbol)
      )
      (zip [0 ..] (T.lines content))

fieldSpan :: Text -> Text -> Maybe Int
fieldSpan line symbol = do
  (prefix, _) <- listToMaybe (T.breakOnAll ("." <> symbol) line)
  pure (T.length prefix + 1)

findWordRange :: Text -> Text -> Maybe (Int, Int, Int)
findWordRange content symbol =
  listToMaybe $
    mapMaybe
      ( \(lineNo, line) ->
          fmap
            ( \startOffset ->
                let (startChar, endChar) = textRangeToUtf16Columns line startOffset (startOffset + T.length symbol)
                 in (lineNo, startChar, endChar)
            )
            (wordSpan line symbol)
      )
      (zip [0 ..] (T.lines content))

wordSpan :: Text -> Text -> Maybe Int
wordSpan line symbol =
  listToMaybe $
    mapMaybe validOffset offsets
 where
  offsets = map (T.length . fst) (T.breakOnAll symbol line)
  validOffset startChar =
    if boundary (startChar - 1) && boundary (startChar + T.length symbol)
      then Just startChar
      else Nothing
  boundary ix
    | ix < 0 = True
    | ix >= T.length line = True
    | otherwise = not (wordChar (T.index line ix))

tokenWidthAt :: Text -> Int -> Int -> Int
tokenWidthAt content lineNo charNo =
  case drop lineNo (T.lines content) of
    line : _ ->
      let width = T.length (T.takeWhile wordChar (T.drop charNo line))
       in max 1 width
    _ -> 1

wordAt :: Int -> Int -> Text -> Text
wordAt lineNo charNo content =
  case drop lineNo (T.lines content) of
    line : _ ->
      case utf16ColumnToTextOffset line charNo of
        Just charOffset -> let (a, b) = T.splitAt charOffset line in takeWordEnd a <> takeWordStart b
        Nothing -> "default"
    _ -> "default"
 where
  ok c = completionChar c
  takeWordEnd = T.reverse . T.takeWhile ok . T.reverse
  takeWordStart = T.takeWhile ok

-- pathUri / uriPath live in 'ServerUri'; re-imported below.

documentPath :: Maybe Value -> Maybe FilePath
documentPath params = do
  textDocument <- field "textDocument" =<< params
  uri <- field "uri" textDocument >>= asText
  pure (uriPath uri)

clearDiagnostics :: FilePath -> Value
clearDiagnostics file = object ["uri" .= pathUri file, "diagnostics" .= ([] :: [Value])]

-- JSON-RPC framing primitives (ReadOutcome, readMessageOutcome,
-- readMessage, readHeaders, contentLengthFromHeaders, send, notify) live
-- in 'ServerProtocol'.

-- | Send a JSON-RPC response that mirrors the @id@ from the request.
respond :: Handle -> Value -> Value -> IO ()
respond handle request result =
  case field "id" request of
    Just ident -> send handle (object ["jsonrpc" .= ("2.0" :: Text), "id" .= ident, "result" .= result])
    Nothing -> pure ()

-- percentEncode / percentDecode / stripAuthority live in 'ServerUri'.
