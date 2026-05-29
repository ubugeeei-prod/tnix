{-# LANGUAGE OverloadedStrings #-}

-- | Top-level parsing entry point.
--
-- This wrapper converts Megaparsec's rich diagnostic bundle into plain text so
-- the rest of the pipeline can forward parse errors through the CLI, LSP, and
-- tests without depending on parser-specific types.
--
-- 'parseProgramDetailed' also exposes a small structured error type so editors
-- can attach diagnostics to the exact line/column instead of column 0.
module Parser
  ( ParseError (..),
    parseProgram,
    parseProgramDetailed,
  )
where

import Control.Monad.Reader (runReaderT)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import ParserExpr
import ParserLexer
import Syntax
import Text.Megaparsec
  ( PosState (..),
    SourcePos (..),
    bundleErrors,
    bundlePosState,
    eof,
    errorBundlePretty,
    errorOffset,
    parseErrorTextPretty,
    reachOffset,
    runParser,
    unPos,
  )

-- | Structured parser diagnostic.
--
-- All offsets are 1-based to match what editors and humans expect; the LSP
-- conversion subtracts 1 when it builds a 0-based LSP `Range`.
data ParseError = ParseError
  { parseErrorLine :: Int,
    parseErrorColumn :: Int,
    parseErrorMessage :: Text
  }
  deriving (Eq, Show)

-- | Parse a complete tnix program, returning a pretty-printed error message
-- on failure. Kept as the back-compatible entry point used by the rest of
-- the pipeline.
parseProgram :: FilePath -> Text -> Either Text Program
parseProgram path = either (Left . renderParseError) Right . parseProgramDetailed path

renderParseError :: ParseError -> Text
renderParseError err =
  Text.pack (show (parseErrorLine err))
    <> ":"
    <> Text.pack (show (parseErrorColumn err))
    <> ": "
    <> parseErrorMessage err

-- | Parse a complete tnix program with structured location info on failure.
parseProgramDetailed :: FilePath -> Text -> Either ParseError Program
parseProgramDetailed path input = do
  directives <- mapDirectiveError input (scanDiagnosticDirectives input)
  case runParser (runReaderT (sc *> programParser <* eof) directives) path input of
    Left bundle -> Left (megaparsecError bundle)
    Right program -> Right program

mapDirectiveError :: Text -> Either Text a -> Either ParseError a
mapDirectiveError _ (Right a) = Right a
mapDirectiveError _ (Left message) =
  Left ParseError{parseErrorLine = 1, parseErrorColumn = 1, parseErrorMessage = message}

-- | Lift the first error in a Megaparsec bundle into our structured form,
-- recovering the offending source line/column from the parser's PosState.
megaparsecError bundle =
  let firstError :| _ = bundleErrors bundle
      (_, finalState) = reachOffset (errorOffset firstError) (bundlePosState bundle)
      SourcePos _ srcLine srcColumn = pstateSourcePos finalState
      humanMessage = Text.pack (errorBundlePretty bundle)
      compactMessage = Text.pack (parseErrorTextPretty firstError)
      message =
        if Text.null humanMessage
          then compactMessage
          else humanMessage
   in ParseError
        { parseErrorLine = unPos srcLine,
          parseErrorColumn = unPos srcColumn,
          parseErrorMessage = message
        }

scanDiagnosticDirectives :: Text -> Either Text DirectiveTargets
scanDiagnosticDirectives input = go 1 Nothing Map.empty (Text.lines input)
  where
    go _ Nothing acc [] = Right acc
    go lineNo (Just _) _ [] = Left ("dangling tnix diagnostic directive before end of file at line " <> Text.pack (show (lineNo - 1)))
    go lineNo pending acc (line : rest) =
      case parseDirective line of
        Just directive ->
          case pending of
            Just _ -> Left ("multiple tnix diagnostic directives target the same next line before line " <> Text.pack (show lineNo))
            Nothing -> go (lineNo + 1) (Just directive) acc rest
        Nothing
          | isSkippableLine line -> go (lineNo + 1) pending acc rest
          | otherwise ->
              case pending of
                Nothing -> go (lineNo + 1) Nothing acc rest
                Just directive ->
                  case Map.lookup lineNo acc of
                    Just _ -> Left ("duplicate tnix diagnostic directives for line " <> Text.pack (show lineNo))
                    Nothing -> go (lineNo + 1) Nothing (Map.insert lineNo directive acc) rest

parseDirective :: Text -> Maybe DiagnosticDirective
parseDirective raw =
  case Text.stripStart raw of
    trimmed
      | Just rest <- Text.stripPrefix "#" trimmed ->
          let body = Text.stripStart rest
           in if "@tnix-ignore" `Text.isPrefixOf` body
                then Just TnixIgnore
                else
                  if "@tnix-expected" `Text.isPrefixOf` body
                    then Just TnixExpected
                    else Nothing
      | otherwise -> Nothing

isSkippableLine :: Text -> Bool
isSkippableLine raw =
  case Text.strip raw of
    "" -> True
    trimmed -> "#" `Text.isPrefixOf` trimmed
