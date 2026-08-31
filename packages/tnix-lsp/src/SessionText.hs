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
wordSpans line symbol
  | Text.null symbol = []
  | otherwise = mapMaybe validOffset (Text.breakOnAll symbol line)
  where
    symbolLength = Text.length symbol
    -- `breakOnAll` hands back the text on either side of each match, so both
    -- neighbours are reachable without indexing into `line`. `Text.index` is
    -- O(n) on `Text`, which made checking every match quadratic in the length
    -- of the line.
    validOffset (prefix, suffix)
      | boundaryBefore prefix && boundaryAfter suffix = Just (Text.length prefix)
      | otherwise = Nothing
    boundaryBefore prefix =
      case Text.unsnoc prefix of
        Nothing -> True
        Just (_, before) -> not (wordChar before)
    boundaryAfter suffix =
      case Text.uncons (Text.drop symbolLength suffix) of
        Nothing -> True
        Just (after, _) -> not (wordChar after)

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
