{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson (Value, object, (.=))
import Data.Text qualified as T
import SessionFolding
import Test.Hspec

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "foldingRangesFor" $ do
    it "returns no ranges for single-line content" $
      foldingRangesFor "let x = 1; in x" `shouldBe` []

    it "folds multi-line let-in across opening and closing keywords" $
      foldingRangesFor (T.unlines ["let", "  x = 1;", "in x"])
        `shouldContain` [FoldingRange 0 2 Nothing]

    it "folds multi-line attribute sets" $
      foldingRangesFor (T.unlines ["{", "  a = 1;", "}"])
        `shouldContain` [FoldingRange 0 2 Nothing]

    it "folds multi-line list literals" $
      foldingRangesFor (T.unlines ["[", "  1", "]"])
        `shouldContain` [FoldingRange 0 2 Nothing]

    it "folds multi-line parenthesised expressions" $
      foldingRangesFor (T.unlines ["(", "  1 + 2", ")"])
        `shouldContain` [FoldingRange 0 2 Nothing]

    it "folds consecutive comment lines of two or more" $
      foldingRangesFor (T.unlines ["# first", "# second", "# third", "x"])
        `shouldContain` [FoldingRange 0 2 (Just "comment")]

    it "does not fold a single comment line" $
      foldingRangesFor (T.unlines ["# alone", "x"]) `shouldBe` []

    it "ignores brackets inside double-quoted strings" $
      foldingRangesFor (T.unlines ["x = \"{[(]}\"", "y = 1"]) `shouldBe` []

    it "folds multi-line indented strings" $
      foldingRangesFor (T.unlines ["msg = ''", "  hello", "''"])
        `shouldContain` [FoldingRange 0 2 Nothing]

    it "treats ''' as an escape inside indented strings" $
      foldingRangesFor (T.unlines ["msg = ''", "  '''", "  inside", "''"])
        `shouldContain` [FoldingRange 0 3 Nothing]

    it "skips brace-like text inside line comments" $
      foldingRangesFor (T.unlines ["a = 1; # { unmatched", "b = 2;"]) `shouldBe` []

    it "matches 'let' only as a whole word, not inside identifiers" $
      foldingRangesFor (T.unlines ["letx = {", "  a = 1;", "};"])
        `shouldContain` [FoldingRange 0 2 Nothing]

    it "matches 'in' only as a whole word, not inside identifiers" $
      foldingRangesFor (T.unlines ["{", "  inner = 1;", "}"])
        `shouldContain` [FoldingRange 0 2 Nothing]

    it "sorts ranges by start line" $ do
      let result =
            foldingRangesFor
              ( T.unlines
                  [ "# a",
                    "# b",
                    "{",
                    "  x = 1;",
                    "}"
                  ]
              )
      map foldingRangeStartLine result `shouldBe` [0, 2]

    it "leaves single-line bracket pairs unfolded" $
      foldingRangesFor "{ a = 1; }" `shouldBe` []

    it "tolerates unbalanced brackets without emitting a range" $
      foldingRangesFor (T.unlines ["{", "  a = 1;"]) `shouldBe` []

  describe "encodeFoldingRanges" $ do
    it "omits kind when absent" $
      encodeFoldingRanges [FoldingRange 1 3 Nothing]
        `shouldBe` ([object ["startLine" .= (1 :: Int), "endLine" .= (3 :: Int)]] :: [Value])

    it "includes kind when present" $
      encodeFoldingRanges [FoldingRange 0 4 (Just "comment")]
        `shouldBe` ( [ object
                        [ "startLine" .= (0 :: Int),
                          "endLine" .= (4 :: Int),
                          "kind" .= ("comment" :: T.Text)
                        ]
                     ]
                       :: [Value]
                   )
