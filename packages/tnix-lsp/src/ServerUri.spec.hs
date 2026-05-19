{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import ServerUri
import Test.Hspec

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "pathUri" $ do
    it "prefixes a plain path with the file:// scheme" $
      pathUri "/tmp/main.tnix" `shouldBe` "file:///tmp/main.tnix"

    it "percent-encodes spaces" $
      pathUri "/tmp/with space/main.tnix"
        `shouldBe` "file:///tmp/with%20space/main.tnix"

    it "percent-encodes non-ASCII identifiers in path segments" $
      pathUri "/tmp/\x578b.tnix" `shouldBe` "file:///tmp/%E5%9E%8B.tnix"

  describe "uriPath" $ do
    it "drops the file:// scheme and returns the underlying path" $
      uriPath "file:///tmp/main.tnix" `shouldBe` "/tmp/main.tnix"

    it "round-trips through percent decoding" $
      uriPath "file:///tmp/with%20space/main.tnix" `shouldBe` "/tmp/with space/main.tnix"

    it "tolerates a localhost authority" $
      uriPath "file://localhost/tmp/main.tnix" `shouldBe` "/tmp/main.tnix"

    it "leaves a non-URI path untouched" $
      uriPath "/tmp/main.tnix" `shouldBe` "/tmp/main.tnix"

  describe "percentEncode / percentDecode" $ do
    it "round-trips spaces" $
      percentDecode (percentEncode "with space") `shouldBe` "with space"

    it "round-trips unicode" $
      percentDecode (percentEncode "型情報") `shouldBe` "型情報"

    it "leaves unreserved characters untouched" $
      percentEncode "abc-_.~/0" `shouldBe` "abc-_.~/0"
