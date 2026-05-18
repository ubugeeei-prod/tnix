{-# LANGUAGE OverloadedStrings #-}

{- | Testable document-session helpers for the tnix language server.

The executable keeps only the stdio loop and an 'IORef' cache. All document
lifecycle behavior lives here so specs can exercise the same update/hover
logic that the real server uses.
-}
module Session (
  Documents,
  closeDocuments,
  codeActionsDocument,
  completionDocument,
  definitionDocument,
  documentsFromList,
  documentSymbolsDocument,
  hoverDocument,
  lookupDocumentText,
  referencesDocument,
  renameDocument,
  semanticTokensDocument,
  updateDocuments,
  workspaceSymbolsDocument,
)
where

import Control.Applicative ((<|>))
import Control.Monad (forM)
import Data.Aeson (Value (..), object, toJSON, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Char (isAlphaNum, isDigit, isLetter, isUpper, toLower)
import Data.List (isSuffixOf, nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Driver (Analysis (..))
import Server (
  applyContentChanges,
  asInt,
  asText,
  completionResult,
  documentPath,
  field,
  findDefinitionRange,
  findFieldRange,
  hoverResult,
  location,
  pathUri,
  textOffsetToUtf16Column,
  textRangeToUtf16Columns,
  uriPath,
  wordAt,
 )
import SessionDocuments
  ( closeDocuments,
    documentsFromList,
    effectiveCachedAnalysis,
    insertDocument,
    loadDocumentAnalysis,
    loadDocumentContent,
    loadWorkspaceDocuments,
    lookupCachedDocument,
    lookupDocumentText,
    updateDocuments,
    workspaceSeedFile,
  )
import SessionReferences
  ( resolveDefinitionLocation,
    resolveReferenceTarget,
    symbolRanges,
    workspaceDocumentsForTarget,
  )
import SessionText (wordChar)
import SessionSymbols
  ( documentCandidateNames,
    documentIndexedSymbols,
    findDeclareRange,
    indexedSymbolInformation,
    kindForType,
    locationFromRange,
    workspaceIndexedSymbols,
  )
import SessionTypes
  ( CachedDocument (..),
    Documents (..),
    IndexedSymbol (..),
    MatchMode (..),
    ReferenceTarget (..),
    SemanticToken (..),
    WorkspaceDocument (..),
  )
import SessionWorkspace
  ( findBuiltinsFile,
    findWorkspaceRoot,
    hasWorkspaceMarker,
    ignoredDirectory,
    isSourceFile,
    workspaceFilesFor,
  )
import Subtyping (resolveType)
import Syntax
import System.FilePath (normalise, takeDirectory, (</>))
import Type

-- Document cache, workspace, symbol index, reference, and semantic-token
-- data types live in 'SessionTypes'; this module re-imports them so existing
-- call sites and tests keep importing them from 'Session'.

-- documentsFromList and lookupDocumentText live in 'SessionDocuments'.

-- (Type definitions moved to 'SessionTypes'.)

-- updateDocuments and closeDocuments live in 'SessionDocuments'.

{- | Compute hover information for the requested position.

Hover prefers the cached document text so editors see immediate results after
unsaved edits. When the file is not cached yet, the helper falls back to
disk and renders a readable error when loading fails.
-}
hoverDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
hoverDocument readDocument analyze docs msg = do
  let params = field "params" msg
      textDocument = params >>= field "textDocument"
      position = params >>= field "position"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
      lineNo = maybe 0 asInt (position >>= field "line")
      charNo = maybe 0 asInt (position >>= field "character")
  contentResult <- loadDocumentContent readDocument docs file
  case contentResult of
    Left err -> pure (hoverResult (Left err) "" lineNo charNo)
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (hoverResult result content lineNo charNo)

{- | Compute completion items for the requested position.

Completion analyzes the latest cached text so editor suggestions can follow
unsaved changes. The payload is still useful when analysis fails because the
helper returns an empty, well-formed completion list instead of crashing the
protocol exchange.
-}
completionDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
completionDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left err -> pure (completionResult (Left err) "" lineNo charNo)
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (completionResult result content lineNo charNo)

{- | Resolve a definition/declaration jump for the requested position.

Top-level names resolve in the current buffer first and then fall back to a
workspace-wide symbol index. Dotted selections additionally search field
declarations so ambient APIs such as `builtins.map` and local attrset fields
behave like editor users expect.
-}
definitionDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
definitionDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure Null
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      workspace <- loadWorkspaceDocuments readDocument analyze docs file
      builtinsFile <- findBuiltinsFile file
      pure $
        maybe
          Null
          (\(targetFile, targetLine, startChar, endChar) -> location targetFile targetLine startChar endChar)
          (resolveDefinitionLocation file content workspace builtinsFile result lineNo charNo)

{- | Compute references for the selected symbol.

Local names stay scoped to the active buffer, while dotted members search the
workspace so shared ambient surfaces and record-field APIs are discoverable.
-}
referencesDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
referencesDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      workspace <- loadWorkspaceDocuments readDocument analyze docs file
      builtinsFile <- findBuiltinsFile file
      pure . toJSON $
        case resolveReferenceTarget file content workspace builtinsFile result lineNo charNo of
          Nothing -> []
          Just target ->
            [ location path foundLine startChar endChar
            | doc <- workspaceDocumentsForTarget workspace target
            , let path = workspaceDocumentFile doc
            , (foundLine, startChar, endChar) <- symbolRanges (workspaceDocumentContent doc) (referenceTargetNeedle target) (referenceTargetMode target)
            ]

{- | Produce a workspace edit that renames the selected symbol.

The rename strategy mirrors 'referencesDocument': plain local names stay in
one file, while member-style names update dotted usages plus declaration
sites across the workspace.
-}
renameDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
renameDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case (contentResult, field "params" msg >>= field "newName" >>= asText) of
    (Right content, Just newName)
      | not (Text.null newName) -> do
          result <- loadDocumentAnalysis readDocument analyze docs file
          workspace <- loadWorkspaceDocuments readDocument analyze docs file
          builtinsFile <- findBuiltinsFile file
          pure $
            case resolveReferenceTarget file content workspace builtinsFile result lineNo charNo of
              Nothing -> Null
              Just target ->
                let edits =
                      [ (path, map (\(foundLine, startChar, endChar) -> textEdit foundLine startChar endChar newName) ranges)
                      | doc <- workspaceDocumentsForTarget workspace target
                      , let path = workspaceDocumentFile doc
                      , let ranges = symbolRanges (workspaceDocumentContent doc) (referenceTargetNeedle target) (referenceTargetMode target)
                      , not (null ranges)
                      ]
                 in workspaceEdit edits
    _ -> pure Null

-- | List document symbols in a flat, editor-friendly shape.
documentSymbolsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
documentSymbolsDocument readDocument analyze docs msg = do
  (file, _, _, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (toJSON (map indexedSymbolInformation (documentIndexedSymbols file content result)))

-- | Search symbols across the surrounding workspace.
workspaceSymbolsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
workspaceSymbolsDocument readDocument analyze docs msg =
  case workspaceSeedFile docs of
    Nothing -> pure (toJSON ([] :: [Value]))
    Just seedFile -> do
      workspace <- loadWorkspaceDocuments readDocument analyze docs seedFile
      let query = Text.toCaseFold (fromMaybe "" (field "params" msg >>= field "query" >>= asText))
          matches symbol =
            Text.null query
              || query `Text.isInfixOf` Text.toCaseFold (indexedSymbolName symbol)
              || maybe False (query `Text.isInfixOf`) (Text.toCaseFold <$> indexedSymbolContainer symbol)
          symbols = take 200 (filter matches (workspaceIndexedSymbols workspace))
      pure (toJSON (map indexedSymbolInformation symbols))

{- | Offer quick fixes for current diagnostics.

The server surfaces lightweight escape hatches (`@tnix-ignore`,
`@tnix-expected`) and, for obvious misspellings, a rename replacement based
on nearby in-scope symbol names.
-}
codeActionsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
codeActionsDocument readDocument analyze docs msg = do
  (file, _, _, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      workspace <- loadWorkspaceDocuments readDocument analyze docs file
      let diagnostics = diagnosticPayloads msg
          candidates = nub (documentCandidateNames result <> map indexedSymbolName (workspaceIndexedSymbols workspace) <> ["builtins", "import"])
          actions =
            concatMap
              ( \diagnostic ->
                  let message = fromMaybe "" (field "message" diagnostic >>= asText)
                      fixes = directiveActions file content diagnostic
                      renameFix =
                        case (diagnosticRange diagnostic, diagnosticSymbolName message, closestCandidate candidates =<< diagnosticSymbolName message) of
                          (Just (lineNo, startChar, endChar), Just current, Just replacement)
                            | current /= replacement ->
                                [ quickFixAction
                                    ("Replace with `" <> replacement <> "`")
                                    file
                                    [textEdit lineNo startChar endChar replacement]
                                ]
                          _ -> []
                   in fixes <> renameFix
              )
              diagnostics
      pure (toJSON actions)

-- | Return LSP semantic tokens for one document.
semanticTokensDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
semanticTokensDocument readDocument analyze docs msg = do
  (file, _, _, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (object ["data" .= ([] :: [Int])])
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (object ["data" .= encodeSemanticTokens (semanticTokensFor content result)])

requestDocument ::
  (FilePath -> IO (Either String Text)) ->
  Documents ->
  Value ->
  IO (FilePath, Int, Int, Either String Text)
requestDocument readDocument docs msg = do
  let params = field "params" msg
      textDocument = params >>= field "textDocument"
      position = params >>= field "position"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
      lineNo = maybe 0 asInt (position >>= field "line")
      charNo = maybe 0 asInt (position >>= field "character")
  contentResult <- loadDocumentContent readDocument docs file
  pure (file, lineNo, charNo, contentResult)

-- loadDocumentContent / loadDocumentAnalysis / loadWorkspaceDocuments live in 'SessionDocuments'.

-- Reference / definition resolution (workspaceDocumentsForTarget,
-- resolveDefinitionLocation, resolveReferenceTarget, symbolRanges,
-- all*Ranges) lives in 'SessionReferences'.

-- Symbol indexing helpers (documentIndexedSymbols, workspaceIndexedSymbols,
-- indexedSymbolInformation, documentCandidateNames, kindForType,
-- findDeclareRange, locationFromRange) live in 'SessionSymbols'.

-- workspaceSeedFile lives in 'SessionDocuments'.

-- Workspace traversal helpers live in 'SessionWorkspace' so they can be
-- unit-tested in isolation. Re-exported here for back-compat with callers
-- that still import them from 'Session'.

-- symbolRanges and all*Ranges live in 'SessionReferences'.

-- Span helpers and character classification live in 'SessionText'.

-- findDeclareRange and kindForType live in 'SessionSymbols'.

textEdit :: Int -> Int -> Int -> Text -> Value
textEdit lineNo startChar endChar newText =
  object
    [ "range" .= rangeValue lineNo startChar endChar
    , "newText" .= newText
    ]

rangeValue :: Int -> Int -> Int -> Value
rangeValue lineNo startChar endChar =
  object
    [ "start" .= object ["line" .= lineNo, "character" .= startChar]
    , "end" .= object ["line" .= lineNo, "character" .= endChar]
    ]

workspaceEdit :: [(FilePath, [Value])] -> Value
workspaceEdit edits =
  object
    [ "changes"
        .= Object
          ( KeyMap.fromList
              [ (Key.fromText (pathUri file), toJSON fileEdits)
              | (file, fileEdits) <- edits
              ]
          )
    ]

diagnosticPayloads :: Value -> [Value]
diagnosticPayloads msg =
  case field "params" msg >>= field "context" >>= field "diagnostics" of
    Just (Array diagnostics) -> toList diagnostics
    _ -> []
 where
  toList = foldr (:) []

diagnosticRange :: Value -> Maybe (Int, Int, Int)
diagnosticRange diagnostic = do
  range <- field "range" diagnostic
  start <- field "start" range
  ending <- field "end" range
  lineNo <- field "line" start
  startChar <- field "character" start
  endChar <- field "character" ending
  pure (asInt lineNo, asInt startChar, asInt endChar)

diagnosticSymbolName :: Text -> Maybe Text
diagnosticSymbolName message = do
  (_, suffix) <- listToMaybe (Text.breakOnAll "\"" message)
  let rest = Text.drop 1 suffix
      (quoted, trailing) = Text.breakOn "\"" rest
  if Text.null trailing then Nothing else Just quoted

directiveActions :: FilePath -> Text -> Value -> [Value]
directiveActions file content diagnostic =
  case diagnosticRange diagnostic of
    Just (lineNo, _, _)
      | not (lineHasDirective "# @tnix-ignore" lineNo content) ->
          [ quickFixAction "Add `# @tnix-ignore`" file [insertLineEdit lineNo "# @tnix-ignore\n"]
          , quickFixAction "Add `# @tnix-expected`" file [insertLineEdit lineNo "# @tnix-expected\n"]
          ]
      | otherwise -> []
    Nothing -> []

insertLineEdit :: Int -> Text -> Value
insertLineEdit lineNo newText =
  object
    [ "range"
        .= object
          [ "start" .= object ["line" .= lineNo, "character" .= (0 :: Int)]
          , "end" .= object ["line" .= lineNo, "character" .= (0 :: Int)]
          ]
    , "newText" .= newText
    ]

lineHasDirective :: Text -> Int -> Text -> Bool
lineHasDirective directive lineNo content =
  case if lineNo <= 0 then [] else drop (lineNo - 1) (Text.lines content) of
    previous : _ -> directive `Text.isPrefixOf` Text.stripStart previous
    [] -> False

quickFixAction :: Text -> FilePath -> [Value] -> Value
quickFixAction title file edits =
  object
    [ "title" .= title
    , "kind" .= ("quickfix" :: Text)
    , "edit" .= workspaceEdit [(file, edits)]
    ]

closestCandidate :: [Text] -> Text -> Maybe Text
closestCandidate candidates needle =
  case sortOn (\candidate -> (nameDistance needle candidate, candidate)) (filter (/= needle) candidates) of
    candidate : _
      | nameDistance needle candidate <= max 2 (Text.length needle `div` 2) -> Just candidate
    _ -> Nothing

nameDistance :: Text -> Text -> Int
nameDistance left right = last (foldl' step [0 .. length rightChars] (zip [1 ..] leftChars))
 where
  leftChars = map toLower (Text.unpack left)
  rightChars = map toLower (Text.unpack right)
  step previousRow (rowIndex, leftChar) =
    scanl
      (\leftCost (columnIndex, rightChar) -> minimum [leftCost + 1, previousRow !! columnIndex + 1, previousRow !! (columnIndex - 1) + substitutionCost leftChar rightChar])
      rowIndex
      (zip [1 ..] rightChars)
  substitutionCost leftChar rightChar
    | leftChar == rightChar = 0
    | otherwise = 1

semanticTokensFor :: Text -> Either String Analysis -> [SemanticToken]
semanticTokensFor content result =
  let functionNames = case result of
        Left _ -> []
        Right analysis ->
          [ name
          | (name, scheme) <- Map.toList (analysisBindings analysis)
          , case schemeType scheme of
              TFun{} -> True
              _ -> False
          ]
      typeNames = case result of
        Left _ -> []
        Right analysis -> map typeAliasName (programAliases (analysisProgram analysis))
      rootFieldNames = case result of
        Left _ -> []
        Right analysis ->
          case analysisRoot analysis of
            Just scheme ->
              case resolveType (analysisAliases analysis) (schemeType scheme) of
                TRecord fields -> Map.keys fields
                _ -> []
            Nothing -> []
   in concatMap (\(lineNo, line) -> semanticTokensForLine functionNames typeNames rootFieldNames lineNo line) (zip [0 ..] (Text.lines content))

semanticTokensForLine :: [Text] -> [Text] -> [Text] -> Int -> Text -> [SemanticToken]
semanticTokensForLine functionNames typeNames rootFieldNames lineNo line = go 0 []
 where
  go index acc
    | index >= Text.length line = reverse acc
    | "#" `Text.isPrefixOf` Text.drop index line = reverse acc
    | otherwise =
        case Text.drop index line of
          rest
            | Just token <- stringToken index rest ->
                go (index + semanticTokenLength token) (clientToken token : acc)
            | Just token <- numberToken index rest ->
                go (index + semanticTokenLength token) (clientToken token : acc)
            | Just token <- operatorToken index rest ->
                go (index + semanticTokenLength token) (clientToken token : acc)
            | Just (tokenText, width) <- identifierToken rest ->
                let token =
                      SemanticToken
                        { semanticTokenLine = lineNo
                        , semanticTokenStart = index
                        , semanticTokenLength = width
                        , semanticTokenType = classifyIdentifier functionNames typeNames rootFieldNames line index tokenText
                        }
                 in go (index + width) (clientToken token : acc)
            | otherwise -> go (index + 1) acc
  clientToken token =
    let startColumn = textOffsetToUtf16Column line (semanticTokenStart token)
        endColumn = textOffsetToUtf16Column line (semanticTokenStart token + semanticTokenLength token)
     in token
          { semanticTokenLine = lineNo
          , semanticTokenStart = startColumn
          , semanticTokenLength = endColumn - startColumn
          }

stringToken :: Int -> Text -> Maybe SemanticToken
stringToken index rest = do
  ('"', _) <- Text.uncons rest
  let body = Text.drop 1 rest
      len =
        case Text.findIndex (== '"') body of
          Just endIx -> endIx + 2
          Nothing -> Text.length rest
  pure SemanticToken{semanticTokenLine = 0, semanticTokenStart = index, semanticTokenLength = len, semanticTokenType = 5}

numberToken :: Int -> Text -> Maybe SemanticToken
numberToken index rest = do
  (char, _) <- Text.uncons rest
  if isDigit char
    then
      let width = Text.length (Text.takeWhile numberChar rest)
       in Just SemanticToken{semanticTokenLine = 0, semanticTokenStart = index, semanticTokenLength = width, semanticTokenType = 6}
    else Nothing
 where
  numberChar c = isDigit c || c `elem` (".eE+-" :: String)

operatorToken :: Int -> Text -> Maybe SemanticToken
operatorToken index rest =
  listToMaybe
    [ SemanticToken{semanticTokenLine = 0, semanticTokenStart = index, semanticTokenLength = Text.length operator, semanticTokenType = 7}
    | operator <- ["::", "->", "%1", ".", "=", "+", "|", "?", ":"]
    , operator `Text.isPrefixOf` rest
    ]

identifierToken :: Text -> Maybe (Text, Int)
identifierToken rest = do
  (char, _) <- Text.uncons rest
  if identStart char
    then
      let tokenText = Text.takeWhile identChar rest
       in Just (tokenText, Text.length tokenText)
    else Nothing

classifyIdentifier :: [Text] -> [Text] -> [Text] -> Text -> Int -> Text -> Int
classifyIdentifier functionNames typeNames rootFieldNames line index token
  | token `elem` reservedWords = 0
  | token `elem` typeNames = 1
  | token `elem` rootFieldNames = 4
  | previousNonSpace line index == Just '.' = 4
  | nextOperator line (index + Text.length token) == Just "::" =
      if lineStartsWithType line
        then 1
        else if token `elem` functionNames then 2 else 4
  | nextOperator line (index + Text.length token) == Just "=" =
      if token `elem` functionNames then 2 else 3
  | Text.any isUpper token && maybe False isUpper (fst <$> Text.uncons token) = 1
  | token `elem` functionNames = 2
  | otherwise = 3

previousNonSpace :: Text -> Int -> Maybe Char
previousNonSpace line index =
  listToMaybe
    [ char
    | char <- reverse (Text.unpack (Text.take index line))
    , not (char `elem` [' ', '\t'])
    ]

nextOperator :: Text -> Int -> Maybe Text
nextOperator line index =
  let suffix = Text.dropWhile (`elem` [' ', '\t']) (Text.drop index line)
   in listToMaybe
        [ operator
        | operator <- ["::", "=", ":"]
        , operator `Text.isPrefixOf` suffix
        ]

lineStartsWithType :: Text -> Bool
lineStartsWithType = ("type " `Text.isPrefixOf`) . Text.stripStart

identStart :: Char -> Bool
identStart char = isLetter char || char == '_'

identChar :: Char -> Bool
identChar char = isAlphaNum char || char `elem` ("_'-" :: String)

reservedWords :: [Text]
reservedWords =
  ["any", "as", "declare", "dynamic", "else", "extends", "false", "forall", "if", "in", "infer", "inherit", "let", "null", "then", "true", "type", "unknown"]

encodeSemanticTokens :: [SemanticToken] -> [Int]
encodeSemanticTokens tokens = snd (foldl step (Nothing, []) (sortOn (\token -> (semanticTokenLine token, semanticTokenStart token)) tokens))
 where
  step (previous, acc) token =
    let deltaLine = maybe (semanticTokenLine token) (\prev -> semanticTokenLine token - semanticTokenLine prev) previous
        deltaStart =
          case previous of
            Just prev
              | semanticTokenLine prev == semanticTokenLine token ->
                  semanticTokenStart token - semanticTokenStart prev
            _ -> semanticTokenStart token
        encoded =
          [ deltaLine
          , deltaStart
          , semanticTokenLength token
          , semanticTokenType token
          , 0
          ]
     in (Just token, acc <> encoded)

-- locationFromRange lives in 'SessionSymbols'.

-- lookupCachedDocument / insertDocument / deleteDocument / effectiveCachedAnalysis live in 'SessionDocuments'.
