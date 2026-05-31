{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import AnalysisCache
import Data.Either (isLeft)
import Test.Hspec

main :: IO ()
main = hspec spec

spec :: Spec
spec = describe "AnalysisCache" $ do
  it "starts empty" $
    analysisCacheSize emptyAnalysisCache `shouldBe` 0

  it "stores and retrieves analysis results" $ do
    let key = ("/tmp/main.tnix", "1")
        cache = insertAnalysisCache key (Left "stub") emptyAnalysisCache
    lookupAnalysisCache key cache `shouldSatisfy` maybe False isLeft
    analysisCacheSize cache `shouldBe` 1

  it "treats identical content under different paths as different keys" $ do
    let content = "1"
        cache =
          insertAnalysisCache ("/a.tnix", content) (Left "alpha")
            . insertAnalysisCache ("/b.tnix", content) (Left "beta")
            $ emptyAnalysisCache
    analysisCacheSize cache `shouldBe` 2
    lookupAnalysisCache ("/a.tnix", content) cache `shouldBe` Just (Left "alpha")
    lookupAnalysisCache ("/b.tnix", content) cache `shouldBe` Just (Left "beta")

  it "replaces the entry when the same key is inserted twice" $ do
    let key = ("/tmp/main.tnix", "1")
        cache =
          insertAnalysisCache key (Left "second")
            . insertAnalysisCache key (Left "first")
            $ emptyAnalysisCache
    analysisCacheSize cache `shouldBe` 1
    lookupAnalysisCache key cache `shouldBe` Just (Left "second")

  it "evicts the oldest entries past the capacity bound" $ do
    let capacity = analysisCacheCapacity
        overshoot = capacity + 10
        keys = [("/file" <> show n <> ".tnix", "stub") | n <- [1 .. overshoot]]
        cache = foldl (\acc (n, key) -> insertAnalysisCache key (Left (show n)) acc) emptyAnalysisCache (zip [1 :: Int ..] keys)
    analysisCacheSize cache `shouldBe` capacity
    -- The first 10 inserts should have been evicted.
    lookupAnalysisCache (head keys) cache `shouldBe` Nothing
    -- The most recent inserts should still be present.
    lookupAnalysisCache (last keys) cache `shouldSatisfy` maybe False isLeft

  it "touches cached entries so eviction follows least-recently-used order" $ do
    let capacity = analysisCacheCapacity
        keys = [("/file" <> show n <> ".tnix", "stub") | n <- [1 .. capacity]]
        fullCache = foldl (\acc (n, key) -> insertAnalysisCache key (Left (show n)) acc) emptyAnalysisCache (zip [1 :: Int ..] keys)
        (hit, touchedCache) = accessAnalysisCache (head keys) fullCache
        evictedCache = insertAnalysisCache ("/extra.tnix", "stub") (Left "extra") touchedCache
    hit `shouldBe` Just (Left "1")
    analysisCacheSize evictedCache `shouldBe` capacity
    lookupAnalysisCache (head keys) evictedCache `shouldBe` Just (Left "1")
    lookupAnalysisCache (keys !! 1) evictedCache `shouldBe` Nothing
