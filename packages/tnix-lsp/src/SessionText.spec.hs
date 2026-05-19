{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import SessionText
import Test.Hspec

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
