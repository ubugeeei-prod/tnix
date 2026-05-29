{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text qualified as T
import SessionLinks
import Test.Hspec

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "findDocumentLinks" $ do
    it "captures the unquoted path after import" $
      findDocumentLinks "import ./legacy/default.nix"
        `shouldBe` [DocumentLink 0 7 27 "./legacy/default.nix"]

    it "captures relative ../ paths" $
      findDocumentLinks "import ../shared/lib.tnix"
        `shouldBe` [DocumentLink 0 7 25 "../shared/lib.tnix"]

    it "captures absolute / paths" $
      findDocumentLinks "import /etc/nix/profile.nix"
        `shouldBe` [DocumentLink 0 7 27 "/etc/nix/profile.nix"]

    it "captures the quoted path after declare" $
      findDocumentLinks "declare \"./registry/builtins.d.tnix\" {"
        `shouldBe` [DocumentLink 0 9 35 "./registry/builtins.d.tnix"]

    it "rejects identifiers that merely start with import or declare" $ do
      findDocumentLinks "importHelper ./foo" `shouldBe` []
      findDocumentLinks "declareHelper \"./foo\"" `shouldBe` []

    it "ignores import keywords that appear inside a line comment" $
      findDocumentLinks "# import ./foo\nlet x = 1; in x" `shouldBe` []

    it "ignores import keywords after a trailing comment marker" $
      findDocumentLinks "x = 1; # import ./foo" `shouldBe` []

    it "still captures imports that appear before a trailing comment" $
      findDocumentLinks "import ./foo.nix # legacy entry"
        `shouldBe` [DocumentLink 0 7 16 "./foo.nix"]

    it "does not match an import keyword inside a quoted string" $
      findDocumentLinks "let label = \"import ./foo\"; in label" `shouldBe` []

    it "does not emit a link when only the bare prefix is present" $ do
      findDocumentLinks "import ./" `shouldBe` []
      findDocumentLinks "import ../" `shouldBe` []
      findDocumentLinks "import /" `shouldBe` []

    it "returns UTF-16 columns when surrounded by non-BMP text" $
      findDocumentLinks "\x1f600 import ./foo.nix"
        `shouldBe` [DocumentLink 0 10 19 "./foo.nix"]

    it "captures multiple links on separate lines" $
      findDocumentLinks
        ( T.unlines
            [ "declare \"./shim.d.tnix\" {",
              "  fst :: a -> b;",
              "};",
              "import ./body.tnix"
            ]
        )
        `shouldBe` [ DocumentLink 0 9 22 "./shim.d.tnix",
                     DocumentLink 3 7 18 "./body.tnix"
                   ]

  describe "resolveLinkTarget" $ do
    it "resolves a relative path against the source file's directory" $
      resolveLinkTarget "/workspace/app" "./lib/util.tnix"
        `shouldBe` "/workspace/app/lib/util.tnix"

    it "collapses .. segments" $
      resolveLinkTarget "/workspace/app/pkg" "../shared/util.tnix"
        `shouldBe` "/workspace/app/shared/util.tnix"

    it "leaves absolute paths untouched" $
      resolveLinkTarget "/workspace/app" "/etc/nix/profile.nix"
        `shouldBe` "/etc/nix/profile.nix"

  describe "encodeDocumentLink" $
    it "emits an LSP wire object with a range and a file:// target" $
      let link = DocumentLink 1 7 16 "./foo.nix"
       in show (encodeDocumentLink "/tmp/proj" link)
            `shouldContain` "file:///tmp/proj/foo.nix"
