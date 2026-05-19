{-# LANGUAGE OverloadedStrings #-}

-- | Folding-range provider for the tnix LSP.
--
-- Produces 'textDocument/foldingRange' responses by scanning the document
-- text for paired brackets (@{}@, @[]@, @()@), @let-in@ blocks, multi-line
-- string literals, and contiguous comment runs. The scan is text-driven so
-- it keeps producing useful folds even when type-checking failed and no
-- 'Driver.Analysis' is available.
module SessionFolding
  ( FoldingRange (..),
    encodeFoldingRanges,
    foldingRangesFor,
  )
where

import Data.Aeson (Value, object, (.=))
import Data.Char (isDigit, isLetter)
import Data.List (foldl', sortOn)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Internal folding-range value type.
--
-- The wire encoding produced by 'encodeFoldingRanges' omits the @kind@
-- field when it is 'Nothing', matching the LSP spec where the field is
-- optional.
data FoldingRange = FoldingRange
  { foldingRangeStartLine :: !Int
  , foldingRangeEndLine :: !Int
  , foldingRangeKind :: !(Maybe Text)
  }
  deriving (Eq, Show)

-- | Encode each folding range into the LSP wire object.
encodeFoldingRanges :: [FoldingRange] -> [Value]
encodeFoldingRanges = map encode1
 where
  encode1 (FoldingRange start end Nothing) =
    object ["startLine" .= start, "endLine" .= end]
  encode1 (FoldingRange start end (Just kind)) =
    object ["startLine" .= start, "endLine" .= end, "kind" .= kind]

-- | Compute folding ranges for the given document text.
--
-- The result is sorted by @startLine@ so editors that rely on stable
-- ordering can stream the response without re-sorting.
foldingRangesFor :: Text -> [FoldingRange]
foldingRangesFor content =
  sortOn foldingRangeStartLine (commentRanges content <> structuralRanges content)

-- * Comment ranges -------------------------------------------------------

-- | Fold runs of two or more consecutive lines whose first non-whitespace
-- character is @#@. Inline trailing comments do not start a new run.
commentRanges :: Text -> [FoldingRange]
commentRanges content =
  let (final, acc) = foldl' step (Nothing, []) (zip [0 ..] (Text.lines content))
   in reverse (finish final acc)
 where
  step (current, acc) (lineNo, line)
    | isCommentLine line = case current of
        Nothing -> (Just (lineNo, lineNo), acc)
        Just (start, _) -> (Just (start, lineNo), acc)
    | otherwise = case current of
        Nothing -> (Nothing, acc)
        Just (start, end) -> (Nothing, flush start end acc)
  finish Nothing acc = acc
  finish (Just (start, end)) acc = flush start end acc
  flush start end acc
    | end > start = FoldingRange start end (Just "comment") : acc
    | otherwise = acc

isCommentLine :: Text -> Bool
isCommentLine line =
  let trimmed = Text.dropWhile (\c -> c == ' ' || c == '\t') line
   in not (Text.null trimmed) && Text.head trimmed == '#'

-- * Structural ranges (brackets, let-in, multi-line strings) -------------

data Bracket = BBrace | BBracket | BParen | BLet
  deriving (Eq, Show)

data ScanMode
  = MNormal
  | MDQuote !Int
  | MIndented !Int
  deriving (Eq, Show)

data ScanState = ScanState
  { scanLine :: !Int
  , scanStack :: ![(Int, Bracket)]
  , scanMode :: !ScanMode
  , scanRanges :: ![FoldingRange]
  }

initialState :: ScanState
initialState = ScanState 0 [] MNormal []

structuralRanges :: Text -> [FoldingRange]
structuralRanges content = reverse (scanRanges (loop content initialState))

loop :: Text -> ScanState -> ScanState
loop txt state
  | Text.null txt = state
  | otherwise = case scanMode state of
      MNormal -> normalStep txt state
      MDQuote _ -> dquoteStep txt state
      MIndented _ -> indentStep txt state

normalStep :: Text -> ScanState -> ScanState
normalStep txt state
  | Text.isPrefixOf "''" txt =
      loop (Text.drop 2 txt) state {scanMode = MIndented (scanLine state)}
  | otherwise =
      let c = Text.head txt
          rest = Text.tail txt
          line = scanLine state
       in case c of
            '\n' -> loop rest state {scanLine = line + 1}
            '#' -> loop (skipToEol rest) state
            '"' -> loop rest state {scanMode = MDQuote line}
            '{' -> openBracket BBrace rest state
            '[' -> openBracket BBracket rest state
            '(' -> openBracket BParen rest state
            '}' -> closeBracket BBrace rest state
            ']' -> closeBracket BBracket rest state
            ')' -> closeBracket BParen rest state
            _
              | isIdentStart c ->
                  let (ident, after) = takeIdent txt
                   in case ident of
                        "let" -> loop after state {scanStack = (line, BLet) : scanStack state}
                        "in" -> loop after (closeLet state)
                        _ -> loop after state
              | otherwise -> loop rest state

openBracket :: Bracket -> Text -> ScanState -> ScanState
openBracket kind rest state =
  loop rest state {scanStack = (scanLine state, kind) : scanStack state}

closeBracket :: Bracket -> Text -> ScanState -> ScanState
closeBracket kind rest state =
  case scanStack state of
    ((startLine, k) : restStack)
      | k == kind ->
          let line = scanLine state
              newRanges
                | line > startLine = FoldingRange startLine line Nothing : scanRanges state
                | otherwise = scanRanges state
           in loop rest state {scanStack = restStack, scanRanges = newRanges}
    _ -> loop rest state

-- | Pop the nearest 'BLet' marker, ignoring any brackets opened in between.
--
-- This mirrors how editors render a folding range for @let-in@: the inner
-- brackets keep their own folds, while the outer @let-in@ wraps from the
-- @let@ keyword to the @in@ keyword.
closeLet :: ScanState -> ScanState
closeLet state =
  let line = scanLine state
      go _ [] = state
      go acc ((startLine, k) : rest)
        | k == BLet =
            let newRanges
                  | line > startLine = FoldingRange startLine line Nothing : scanRanges state
                  | otherwise = scanRanges state
             in state {scanStack = reverse acc <> rest, scanRanges = newRanges}
        | otherwise = go ((startLine, k) : acc) rest
   in go [] (scanStack state)

dquoteStep :: Text -> ScanState -> ScanState
dquoteStep txt state
  | Text.null txt = state
  | otherwise =
      let c = Text.head txt
          rest = Text.tail txt
       in case c of
            '\n' -> loop rest state {scanLine = scanLine state + 1}
            '\\' | not (Text.null rest) ->
              let c2 = Text.head rest
                  rest2 = Text.tail rest
                  state'
                    | c2 == '\n' = state {scanLine = scanLine state + 1}
                    | otherwise = state
               in loop rest2 state'
            '"' ->
              let startLine = case scanMode state of
                    MDQuote n -> n
                    _ -> scanLine state
                  line = scanLine state
                  newRanges
                    | line > startLine = FoldingRange startLine line Nothing : scanRanges state
                    | otherwise = scanRanges state
               in loop rest state {scanMode = MNormal, scanRanges = newRanges}
            _ -> loop rest state

indentStep :: Text -> ScanState -> ScanState
indentStep txt state
  | Text.null txt = state
  | Text.isPrefixOf "'''" txt = loop (Text.drop 3 txt) state
  | Text.isPrefixOf "''$" txt = loop (Text.drop 3 txt) state
  | Text.isPrefixOf "''\\" txt = loop (Text.drop 3 txt) state
  | Text.isPrefixOf "''" txt =
      let startLine = case scanMode state of
            MIndented n -> n
            _ -> scanLine state
          line = scanLine state
          newRanges
            | line > startLine = FoldingRange startLine line Nothing : scanRanges state
            | otherwise = scanRanges state
       in loop (Text.drop 2 txt) state {scanMode = MNormal, scanRanges = newRanges}
  | otherwise =
      let c = Text.head txt
          rest = Text.tail txt
       in if c == '\n'
            then loop rest state {scanLine = scanLine state + 1}
            else loop rest state

-- * Identifier / lexical helpers ------------------------------------------

skipToEol :: Text -> Text
skipToEol = snd . Text.break (== '\n')

isIdentStart :: Char -> Bool
isIdentStart c = isLetter c || c == '_'

isIdentCont :: Char -> Bool
isIdentCont c =
  isLetter c
    || isDigit c
    || c == '_'
    || c == '\''
    || c == '-'
    || c == '?'
    || c == '!'

takeIdent :: Text -> (Text, Text)
takeIdent = Text.span isIdentCont
