{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Alias
import Data.Map.Strict qualified as Map
import Test.Hspec
import Type

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "flattenUnion" $ do
    it "leaves non-union types unchanged" $
      flattenUnion tInt `shouldBe` tInt

    it "collapses single-element unions to the underlying type" $
      flattenUnion (TUnion [tInt]) `shouldBe` tInt

    it "lifts nested unions into a flat list" $
      flattenUnion (TUnion [tInt, TUnion [tString, TUnion [tBool, tNat]]])
        `shouldBe` TUnion [tInt, tString, tBool, tNat]

    it "removes duplicates while preserving the first-seen order" $
      flattenUnion (TUnion [tInt, tString, tInt, TUnion [tString, tBool]])
        `shouldBe` TUnion [tInt, tString, tBool]

    it "preserves an empty union representation" $
      flattenUnion (TUnion []) `shouldBe` TUnion []

  describe "collectApps" $ do
    it "returns the type unchanged when there are no applications" $
      collectApps tInt `shouldBe` (tInt, [])

    it "splits a left-associated application chain head-first" $
      collectApps (TApp (TApp (TCon "Pair") tInt) tString)
        `shouldBe` (TCon "Pair", [tInt, tString])

    it "stops at the leftmost non-application head" $
      collectApps (TApp (TVar "f") tInt)
        `shouldBe` (TVar "f", [tInt])

  describe "expandAliases" $ do
    let env =
          mkAliasEnv
            [ TypeAlias{typeAliasName = "Id", typeAliasParams = [], typeAliasBody = tInt},
              TypeAlias{typeAliasName = "Pair", typeAliasParams = ["a", "b"], typeAliasBody = TRecord (Map.fromList [("fst", TVar "a"), ("snd", TVar "b")])},
              TypeAlias{typeAliasName = "Forever", typeAliasParams = [], typeAliasBody = TCon "Forever"}
            ]

    it "leaves unrelated types untouched" $
      expandAliases env tBool `shouldBe` tBool

    it "expands nullary aliases recursively" $
      expandAliases env (TCon "Id") `shouldBe` tInt

    it "substitutes parameters when reducing parameterized aliases" $
      expandAliases env (TApp (TApp (TCon "Pair") tInt) tString)
        `shouldBe` TRecord (Map.fromList [("fst", tInt), ("snd", tString)])

    it "preserves leftover arguments past the alias arity" $
      expandAliases env (TApp (TApp (TApp (TCon "Pair") tInt) tString) tBool)
        `shouldBe` TApp (TRecord (Map.fromList [("fst", tInt), ("snd", tString)])) tBool

    it "terminates on self-referential aliases instead of looping forever" $
      expandAliases env (TCon "Forever") `shouldBe` TCon "Forever"

    it "rewrites parameters inside nested records" $
      expandAliases env (TRecord (Map.fromList [("value", TApp (TApp (TCon "Pair") tInt) tBool)]))
        `shouldBe` TRecord
          ( Map.fromList
              [ ("value", TRecord (Map.fromList [("fst", tInt), ("snd", tBool)]))
              ]
          )

  describe "matchPattern" $ do
    it "binds a single infer variable to the matched type" $
      matchPattern tInt (TInfer "a")
        `shouldBe` Just (Map.fromList [("a", tInt)])

    it "matches concrete patterns without binding when the shape is equal" $
      matchPattern (TRecord (Map.fromList [("value", tInt)])) (TRecord (Map.fromList [("value", tInt)]))
        `shouldBe` Just Map.empty

    it "captures inner positions through structural patterns" $
      matchPattern
        (TFun Many tInt tString)
        (TFun Many (TInfer "argument") (TInfer "result"))
        `shouldBe` Just (Map.fromList [("argument", tInt), ("result", tString)])

    it "rejects record patterns whose required fields are missing in the actual" $
      matchPattern (TRecord (Map.fromList [("foo", tInt)])) (TRecord (Map.fromList [("bar", TInfer "x")]))
        `shouldBe` Nothing

    it "rejects type-list patterns with a different arity" $
      matchPattern (TTypeList [tInt, tString]) (TTypeList [TInfer "x"])
        `shouldBe` Nothing

    it "requires repeated infer variables to bind to equal types" $ do
      matchPattern (TTypeList [tInt, tInt]) (TTypeList [TInfer "x", TInfer "x"])
        `shouldBe` Just (Map.fromList [("x", tInt)])
      matchPattern (TTypeList [tInt, tString]) (TTypeList [TInfer "x", TInfer "x"])
        `shouldBe` Nothing

    it "matches type application patterns positionally" $
      matchPattern
        (TApp (TCon "List") tInt)
        (TApp (TCon "List") (TInfer "element"))
        `shouldBe` Just (Map.fromList [("element", tInt)])
