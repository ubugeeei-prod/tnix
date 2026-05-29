{-# LANGUAGE OverloadedStrings #-}

-- | Semantic-tokens provider for tnix LSP.
--
-- Produces the per-token list and the LSP-encoded delta stream that the
-- `textDocument/semanticTokens/full` request expects. Token types match the
-- legend advertised by the server in @initializeResult@.
module SessionSemanticTokens
  ( encodeSemanticTokens,
    semanticTokensFor,
  )
where

import Data.Char (isAlphaNum, isDigit, isLetter, isUpper)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Driver (Analysis (..))
import Server (textOffsetToUtf16Column)
import SessionTypes (SemanticToken (..))
import Subtyping (resolveType)
import Syntax (Program (programAliases))
import Type
  ( Scheme (schemeType),
    Type (..),
    TypeAlias (typeAliasName),
  )

-- | Produce the per-document token list ready for `encodeSemanticTokens`.
--
-- The set of "known" function / type / root field names is extracted from
-- the analysis result so highlighting matches the symbol table the LSP
-- already reasoned about.
semanticTokensFor :: Text -> Either String Analysis -> [SemanticToken]
semanticTokensFor content result =
  let functionNames = case result of
        Left _ -> []
        Right analysis ->
          [ name
          | (name, scheme) <- Map.toList (analysisBindings analysis),
            case schemeType scheme of
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
   in concatMap (uncurry (semanticTokensForLine functionNames typeNames rootFieldNames)) (zip [0 ..] (Text.lines content))

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
                          { semanticTokenLine = lineNo,
                            semanticTokenStart = index,
                            semanticTokenLength = width,
                            semanticTokenType = classifyIdentifier functionNames typeNames rootFieldNames line index tokenText
                          }
                   in go (index + width) (clientToken token : acc)
              | otherwise -> go (index + 1) acc
    clientToken token =
      let startColumn = textOffsetToUtf16Column line (semanticTokenStart token)
          endColumn = textOffsetToUtf16Column line (semanticTokenStart token + semanticTokenLength token)
       in token
            { semanticTokenLine = lineNo,
              semanticTokenStart = startColumn,
              semanticTokenLength = endColumn - startColumn
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
    | operator <- ["::", "->", "%1", ".", "=", "+", "|", "?", ":"],
      operator `Text.isPrefixOf` rest
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
  | Text.any isUpper token && maybe False (isUpper . fst) (Text.uncons token) = 1
  | token `elem` functionNames = 2
  | otherwise = 3

previousNonSpace :: Text -> Int -> Maybe Char
previousNonSpace line index =
  listToMaybe
    [ char
    | char <- reverse (Text.unpack (Text.take index line)),
      char `notElem` [' ', '\t']
    ]

nextOperator :: Text -> Int -> Maybe Text
nextOperator line index =
  let suffix = Text.dropWhile (`elem` [' ', '\t']) (Text.drop index line)
   in listToMaybe
        [ operator
        | operator <- ["::", "=", ":"],
          operator `Text.isPrefixOf` suffix
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

-- | Convert the per-token list into the LSP integer delta stream that the
-- spec requires.
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
            [ deltaLine,
              deltaStart,
              semanticTokenLength token,
              semanticTokenType token,
              0
            ]
       in (Just token, acc <> encoded)
