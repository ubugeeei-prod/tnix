{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text (Text)
import Data.Text qualified as Text
import SessionText
import Test.Hspec
import Test.QuickCheck

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "definitionSpans" $ do
    it "matches a `type X =` declaration with indent preserved" $
      definitionSpans "  type Box = a;" "Box" `shouldBe` [(7, 10)]

    it "matches a `name :: T;` signature on its declaration line" $
      definitionSpans "value :: Int;" "value" `shouldBe` [(0, 5)]

    it "matches a `name = ...;` binding on its declaration line" $
      definitionSpans "value = 1;" "value" `shouldBe` [(0, 5)]

    it "returns no span for unrelated text" $
      definitionSpans "  let foo = 1;" "bar" `shouldBe` []

  describe "fieldSpans" $ do
    it "skips the leading dot and returns the field offset" $
      fieldSpans "record.value" "value" `shouldBe` [7]

    it "finds every occurrence on a line" $
      fieldSpans "a.value + b.value" "value" `shouldBe` [2, 12]

    it "does not match a bare identifier" $
      fieldSpans "value + 1" "value" `shouldBe` []

  describe "wordSpans" $ do
    it "matches a whole-word identifier" $
      wordSpans "value + value" "value" `shouldBe` [0, 8]

    it "rejects matches inside larger identifiers" $
      wordSpans "valueExtra" "value" `shouldBe` []

    it "treats start-of-line and end-of-line as word boundaries" $
      wordSpans "value" "value" `shouldBe` [0]

    it "respects identifier characters when finding boundaries" $
      wordSpans "tag-name" "tag" `shouldBe` []

    it "matches at the very start and very end of a line" $ do
      wordSpans "value = value" "value" `shouldBe` [0, 8]
      wordSpans "( value )" "value" `shouldBe` [2]
      wordSpans "x value" "value" `shouldBe` [2]

    it "rejects a match glued to an identifier character on either side" $ do
      wordSpans "avalue" "value" `shouldBe` []
      wordSpans "value?" "value" `shouldBe` []
      wordSpans "value'" "value" `shouldBe` []
      wordSpans "_value_" "value" `shouldBe` []

    it "finds every whole-word occurrence, including adjacent ones" $
      wordSpans "a a a" "a" `shouldBe` [0, 2, 4]

    it "counts offsets in characters, not bytes" $
      -- The LSP layer converts these offsets to UTF-16 columns itself, so this
      -- one must stay in characters even when the line is not ASCII.
      wordSpans "\28450\23383 value" "value" `shouldBe` [3]

    it "returns nothing for an empty needle" $
      wordSpans "value" "" `shouldBe` []

    it "agrees with a direct scan over every offset" $
      property $ \(WordLine line) (Needle needle) ->
        wordSpans line needle === referenceWordSpans line needle

  describe "wordChar" $ do
    it "accepts identifier characters" $ do
      wordChar 'a' `shouldBe` True
      wordChar 'Z' `shouldBe` True
      wordChar '0' `shouldBe` True
      wordChar '_' `shouldBe` True
      wordChar '-' `shouldBe` True
      wordChar '\'' `shouldBe` True
      wordChar '?' `shouldBe` True
      wordChar '!' `shouldBe` True

    it "rejects punctuation and whitespace" $ do
      wordChar ' ' `shouldBe` False
      wordChar '.' `shouldBe` False
      wordChar ':' `shouldBe` False
      wordChar '(' `shouldBe` False

-- | Straightforward definition of a whole-word match, used to hold the
-- optimized scanner to the behaviour it replaced.
referenceWordSpans :: Text -> Text -> [Int]
referenceWordSpans line needle
  | Text.null needle = []
  | otherwise =
      [ offset
      | offset <- [0 .. Text.length line - Text.length needle],
        Text.take (Text.length needle) (Text.drop offset line) == needle,
        boundary (offset - 1),
        boundary (offset + Text.length needle)
      ]
  where
    boundary index
      | index < 0 = True
      | index >= Text.length line = True
      | otherwise = not (wordChar (Text.index line index))

-- | Short lines built from identifier and separator characters so word
-- boundaries land in interesting places.
newtype WordLine = WordLine Text
  deriving (Show)

instance Arbitrary WordLine where
  arbitrary = WordLine . Text.pack <$> resize 12 (listOf (elements "ab_-' .():"))
  shrink (WordLine line) = WordLine . Text.pack <$> shrink (Text.unpack line)

-- | Needles drawn from the same alphabet, kept short so matches are frequent.
newtype Needle = Needle Text
  deriving (Show)

instance Arbitrary Needle where
  arbitrary = Needle . Text.pack <$> resize 3 (listOf (elements "ab_-."))
  shrink (Needle needle) = Needle . Text.pack <$> shrink (Text.unpack needle)
