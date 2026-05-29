{-# LANGUAGE OverloadedStrings #-}

-- | Pure text-level helpers used by the LSP session for symbol search and
-- definition/reference resolution.
--
-- These functions operate on raw 'Text' input and return character offsets
-- into the corresponding line. They are intentionally free of any LSP
-- framing or UTF-16 conversion: callers in 'Session' lift each offset into
-- the appropriate column system. Keeping the layer pure makes the
-- character/offset arithmetic unit-testable on its own.
module SessionText
  ( -- * Span helpers (raw character offsets into a single line)
    definitionSpans,
    fieldSpans,
    wordSpans,

    -- * Character classification
    wordChar,
  )
where

import Data.Char (isAlphaNum)
import Data.List (nub)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Find every offset on @line@ where @symbol@ is bound by a tnix
-- definition form (alias, signature, or binding).
--
-- The returned pairs are @(startOffset, endOffset)@ into the raw line
-- (no UTF-16 conversion). Callers handle indentation by reading from
-- @stripStart@ and adding back the original prefix length.
definitionSpans :: Text -> Text -> [(Int, Int)]
definitionSpans line symbol =
  let stripped = Text.stripStart line
      indent = Text.length line - Text.length stripped
      candidates =
        [ "type " <> symbol,
          symbol <> "::",
          symbol <> " ::",
          symbol <> "=",
          symbol <> " ="
        ]
   in nub
        [ (indent + startChar, indent + startChar + Text.length symbol)
        | candidate <- candidates,
          let (prefix, suffix) = Text.breakOn candidate stripped,
          not (Text.null suffix),
          let startChar = Text.length prefix + if "type " `Text.isPrefixOf` candidate then 5 else 0
        ]

-- | Every offset of @"." <> symbol@ in @line@, plus 1 to skip the dot so
-- the returned offset points at the field name itself.
fieldSpans :: Text -> Text -> [Int]
fieldSpans line symbol =
  [ Text.length prefix + 1
  | (prefix, _) <- Text.breakOnAll ("." <> symbol) line
  ]

-- | Every word-boundary-bounded occurrence of @symbol@ in @line@.
--
-- A boundary is the start/end of the line or any character that is not
-- considered part of a tnix identifier ('wordChar').
wordSpans :: Text -> Text -> [Int]
wordSpans line symbol =
  mapMaybe validOffset offsets
  where
    offsets = map (Text.length . fst) (Text.breakOnAll symbol line)
    validOffset startChar =
      if boundary (startChar - 1) && boundary (startChar + Text.length symbol)
        then Just startChar
        else Nothing
    boundary ix
      | ix < 0 = True
      | ix >= Text.length line = True
      | otherwise = not (wordChar (Text.index line ix))

-- | Predicate for characters that count as part of a tnix identifier.
--
-- This is the inverse of "word boundary" for the purposes of 'wordSpans'.
-- The set is intentionally generous so that `?` and `!` (used in
-- builtin-like names) do not split an otherwise-contiguous identifier.
wordChar :: Char -> Bool
wordChar char =
  char == '_'
    || char == '-'
    || char == '\''
    || char == '?'
    || char == '!'
    || isAlphaNum char
