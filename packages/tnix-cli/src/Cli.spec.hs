{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Cli (Command (..), OutputFormat (..), commandOutputFormat, commandOutputPath, commandParser, executeCommand, lspCommandArgs, renderAnalysis, renderVersion, writeOutput)
import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.List (intercalate, isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Driver (Analysis (..))
import Options.Applicative (ParserPrefs, ParserResult (..), defaultPrefs, execParserPure, getParseResult, info, renderFailure)
import System.Directory (createDirectory, createDirectoryIfMissing, createDirectoryLink, doesFileExist, getTemporaryDirectory, listDirectory, removeFile, removePathForcibly)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, openTempFile)
import System.Timeout (timeout)
import Test.Hspec
import Type

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "commandParser" $ do
    it "parses compile with output" $
      parse ["compile", "main.tnix", "-o", "dist/main.nix"]
        `shouldBe` Just (Compile "main.tnix" (Just "dist/main.nix"))

    it "parses check, emit, init, scaffold, and project commands" $ do
      parse ["check", "main.tnix"] `shouldBe` Just (Check "main.tnix" TextFormat)
      parse ["check", "main.tnix", "--format", "json"] `shouldBe` Just (Check "main.tnix" JsonFormat)
      parse ["emit", "main.tnix"] `shouldBe` Just (Emit "main.tnix" Nothing)
      parse ["init"] `shouldBe` Just (Init Nothing)
      parse ["scaffold", "demo"] `shouldBe` Just (Scaffold (Just "demo"))
      parse ["check-project"] `shouldBe` Just (CheckProject Nothing TextFormat)
      parse ["build", "demo", "--format", "json"] `shouldBe` Just (BuildProject (Just "demo") JsonFormat)
      parse ["emit-project", "demo"] `shouldBe` Just (EmitProject (Just "demo") TextFormat)
      parse ["version"] `shouldBe` Just (Version TextFormat)
      parse ["version", "--format", "json"] `shouldBe` Just (Version JsonFormat)
      parse ["lsp"] `shouldBe` Just (Lsp Nothing)
      parse ["lsp", "--log-file", "tnix-lsp.log"] `shouldBe` Just (Lsp (Just "tnix-lsp.log"))

    it "reports an error for missing subcommands" $ do
      case parserResult [] of
        Failure failure ->
          let (message, _) = renderFailure failure ""
           in message `shouldSatisfy` ("Missing: COMMAND" `isInfixOf`)
        other -> expectationFailure ("expected parse failure, got " <> show other)

  describe "renderAnalysis" $
    it "renders root schemes before named bindings" $ do
      let analysis =
            Analysis
              { analysisProgram = error "unused in cli tests",
                analysisRoot = Just (Scheme [] tInt),
                analysisBindings = Map.fromList [("box", Scheme [] tString), ("id", Scheme ["a"] (TFun Many (TVar "a") (TVar "a")))],
                analysisAliases = mempty,
                analysisAmbient = mempty
              }
      renderAnalysis analysis
        `shouldBe` Text.unlines ["root: Int", "box :: String", "id :: forall a. a -> a"]

  describe "commandOutputPath" $
    it "tracks explicit destinations only for write commands" $ do
      commandOutputPath (Compile "main.tnix" (Just "dist/main.nix")) `shouldBe` Just "dist/main.nix"
      commandOutputPath (Emit "main.tnix" (Just "types/main.d.tnix")) `shouldBe` Just "types/main.d.tnix"
      commandOutputPath (Check "main.tnix" TextFormat) `shouldBe` Nothing
      commandOutputPath (Init Nothing) `shouldBe` Nothing
      commandOutputPath (Scaffold Nothing) `shouldBe` Nothing
      commandOutputPath (Version TextFormat) `shouldBe` Nothing
      commandOutputPath (Lsp Nothing) `shouldBe` Nothing

  describe "commandOutputFormat" $
    it "tracks commands that can emit machine-readable reports" $ do
      commandOutputFormat (Check "main.tnix" JsonFormat) `shouldBe` Just JsonFormat
      commandOutputFormat (CheckProject Nothing TextFormat) `shouldBe` Just TextFormat
      commandOutputFormat (BuildProject Nothing JsonFormat) `shouldBe` Just JsonFormat
      commandOutputFormat (EmitProject Nothing JsonFormat) `shouldBe` Just JsonFormat
      commandOutputFormat (Version JsonFormat) `shouldBe` Just JsonFormat
      commandOutputFormat (Compile "main.tnix" Nothing) `shouldBe` Nothing
      commandOutputFormat (Init Nothing) `shouldBe` Nothing
      commandOutputFormat (Lsp Nothing) `shouldBe` Nothing

  describe "lspCommandArgs" $
    it "delegates to the standalone server over stdio" $ do
      lspCommandArgs Nothing `shouldBe` ["--stdio"]
      lspCommandArgs (Just "tnix-lsp.log") `shouldBe` ["--stdio", "--log-file", "tnix-lsp.log"]

  describe "renderVersion" $ do
    it "renders text and json version output" $ do
      renderVersion "1.2.3" TextFormat `shouldBe` "tnix 1.2.3"
      let json = renderVersion "1.2.3" JsonFormat
      Text.isInfixOf "\"schemaVersion\":1" json `shouldBe` True
      Text.isInfixOf "\"action\":\"version\"" json `shouldBe` True
      Text.isInfixOf "\"version\":\"1.2.3\"" json `shouldBe` True

  describe "executeCommand" $ do
    it "compiles source files through the driver end-to-end" $
      withTempTree
        [ ( "main.tnix",
            source
              [ "let",
                "  value :: Int;",
                "  value = 1;",
                "in value"
              ]
          )
        ]
        ( \root -> do
            output <- executeCommand (Compile (root <> "/main.tnix") Nothing) >>= expectRight
            output `shouldBe` Text.stripEnd (source ["let", "  value = 1;", "in value"])
        )

    it "renders check output for analyzed files" $
      withTempTree
        [ ( "main.tnix",
            source
              [ "let",
                "  id :: forall a. a -> a;",
                "  id = x: x;",
                "in id"
              ]
          )
        ]
        ( \root -> do
            output <- executeCommand (Check (root <> "/main.tnix") TextFormat) >>= expectRight
            Text.lines output `shouldBe` ["root: forall t0. t0 -> t0", "id :: forall a. a -> a"]
        )

    it "renders json check output for analyzed files" $
      withTempTree
        [("main.tnix", "1")]
        ( \root -> do
            output <- executeCommand (Check (root <> "/main.tnix") JsonFormat) >>= expectRight
            Text.isInfixOf "\"schemaVersion\":1" output `shouldBe` True
            Text.isInfixOf "\"success\":true" output `shouldBe` True
            Text.isInfixOf "\"root\":\"1\"" output `shouldBe` True
        )

    it "emits declaration files through the driver end-to-end" $
      withTempTree [("main.tnix", "{ value = 1; }")] $
        \root -> do
          output <- executeCommand (Emit (root <> "/main.tnix") Nothing) >>= expectRight
          output
            `shouldBe` Text.stripEnd
              (source ["declare \"./main.nix\" {", "  value :: 1;", "};"])

    it "surfaces driver failures without writing partial output" $
      withTempTree [("types.d.tnix", "declare \"./lib.nix\" { default :: Int; };")] $
        \root ->
          executeCommand (Compile (root <> "/types.d.tnix") Nothing)
            >>= (`expectLeftContaining` "declaration-only")

    it "surfaces missing source files as user-facing errors" $
      executeCommand (Check "/tmp/tnix-cli-missing/main.tnix" TextFormat)
        >>= (`expectLeftContaining` "failed to read")

    it "renders check failures as json when json output is requested" $
      executeCommand (Check "/tmp/tnix-cli-missing/main.tnix" JsonFormat)
        >>= (`expectLeftContaining` "\"success\":false")

    it "initializes a project with tnix.config.tnix and starter files" $
      withTempTree [] $ \root -> do
        output <- executeCommand (Init (Just root)) >>= expectRight
        let configPath = root </> "tnix.config.tnix"
            configDeclPath = root </> "tnix.config.d.tnix"
            entryPath = root </> "src/main.tnix"
            builtinsPath = root </> "types/builtins.d.tnix"
        doesFileExist configPath `shouldReturn` True
        doesFileExist configDeclPath `shouldReturn` True
        doesFileExist entryPath `shouldReturn` True
        doesFileExist builtinsPath `shouldReturn` True
        -- Atomic write should leave no `*.tmp*` siblings around once init succeeds.
        rootEntries <- listDirectory root
        any (".tmp" `isInfixOf`) rootEntries `shouldBe` False
        srcEntries <- listDirectory (root </> "src")
        any (".tmp" `isInfixOf`) srcEntries `shouldBe` False
        typesEntries <- listDirectory (root </> "types")
        any (".tmp" `isInfixOf`) typesEntries `shouldBe` False
        config <- TextIO.readFile configPath
        configDecl <- TextIO.readFile configDeclPath
        entry <- TextIO.readFile entryPath
        Text.isInfixOf "sourceDir = ./src;" config `shouldBe` True
        Text.isInfixOf "declarationPacks = [];" config `shouldBe` True
        Text.isInfixOf "declare \"./tnix.config.tnix\"" configDecl `shouldBe` True
        Text.isInfixOf "declarationPacks :: List TnixProjectPath;" configDecl `shouldBe` True
        Text.isInfixOf "Hello from" entry `shouldBe` True
        Text.isInfixOf "tnix.config.tnix" output `shouldBe` True

    it "escapes generated string literals during project initialization" $
      withTempTree [] $ \root -> do
        let projectRoot = root </> "quote\"and\\slash"
        _ <- executeCommand (Init (Just projectRoot)) >>= expectRight
        config <- TextIO.readFile (projectRoot </> "tnix.config.tnix")
        entry <- TextIO.readFile (projectRoot </> "src/main.tnix")
        Text.isInfixOf "name = \"quote\\\"and\\\\slash\";" config `shouldBe` True
        Text.isInfixOf "greeting = \"Hello from quote\\\"and\\\\slash\";" entry `shouldBe` True
        _ <- executeCommand (Scaffold (Just projectRoot)) >>= expectRight
        _ <- executeCommand (Check (projectRoot </> "src/main.tnix") TextFormat) >>= expectRight
        pure ()

    it "scaffolds from tnix.config.tnix path overrides without overwriting existing files"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"demo\";",
                "  sourceDir = ./app;",
                "  entry = ./app/custom.tnix;",
                "  declarationDir = \"./decls\";",
                "  builtins = true;",
                "}"
              ]
          ),
          ("app/custom.tnix", "existing")
        ]
      $ \root -> do
        output <- executeCommand (Scaffold (Just root)) >>= expectRight
        doesFileExist (root </> "tnix.config.d.tnix") `shouldReturn` True
        TextIO.readFile (root </> "app/custom.tnix") `shouldReturn` "existing"
        doesFileExist (root </> "decls/builtins.d.tnix") `shouldReturn` True
        Text.isInfixOf "skipped" output `shouldBe` True
        Text.isInfixOf "builtins.d.tnix" output `shouldBe` True
        Text.isInfixOf "tnix.config.d.tnix" output `shouldBe` True

    it "respects builtins = false when scaffolding"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"demo\";",
                "  builtins = false;",
                "}"
              ]
          )
        ]
      $ \root -> do
        _ <- executeCommand (Scaffold (Just root)) >>= expectRight
        doesFileExist (root </> "src/main.tnix") `shouldReturn` True
        doesFileExist (root </> "types/builtins.d.tnix") `shouldReturn` False

    it "reports missing or invalid scaffold configs" $
      withTempTree [] (\root -> executeCommand (Scaffold (Just root)) >>= (`expectLeftContaining` "missing tnix.config.tnix"))
        >> withTempTree
          [("tnix.config.tnix", "{ builtins = 1; }")]
          (\root -> executeCommand (Scaffold (Just root)) >>= (`expectLeftContaining` "expected Bool for builtins"))

    it "checks every discovered source file in a project"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"demo\";",
                "  sourceDir = ./src;",
                "  exclude = [ ./src/skip ];",
                "}"
              ]
          ),
          ("src/main.tnix", "1"),
          ("src/lib/util.tnix", "\"ok\""),
          ("src/skip/ignored.tnix", "missing")
        ]
      $ \root -> do
        output <- executeCommand (CheckProject (Just root) TextFormat) >>= expectRight
        Text.isInfixOf "src/main.tnix" output `shouldBe` True
        Text.isInfixOf "src/lib/util.tnix" output `shouldBe` True
        Text.isInfixOf "ignored.tnix" output `shouldBe` False

    it "builds a project into compiled nix and generated declarations"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"demo\";",
                "  sourceDir = ./src;",
                "  buildDir = ./artifacts;",
                "  generatedDeclarationDir = ./artifacts/types;",
                "}"
              ]
          ),
          ( "src/main.tnix",
            source
              [ "let",
                "  value :: Int;",
                "  value = 1;",
                "in value"
              ]
          )
        ]
      $ \root -> do
        output <- executeCommand (BuildProject (Just root) TextFormat) >>= expectRight
        doesFileExist (root </> "artifacts/main.nix") `shouldReturn` True
        doesFileExist (root </> "artifacts/types/main.d.tnix") `shouldReturn` True
        declaration <- TextIO.readFile (root </> "artifacts/types/main.d.tnix")
        Text.isInfixOf "declare \"../main.nix\"" declaration `shouldBe` True
        Text.isInfixOf "artifacts/main.nix" output `shouldBe` True

    it "does not write project build outputs when any source fails"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"demo\";",
                "  sourceDir = ./src;",
                "  buildDir = ./artifacts;",
                "  generatedDeclarationDir = ./artifacts/types;",
                "}"
              ]
          ),
          ("src/a.tnix", "1"),
          ("src/b.tnix", "missing")
        ]
      $ \root -> do
        result <- executeCommand (BuildProject (Just root) TextFormat)
        case result of
          Left report -> do
            Text.isInfixOf "- ok src/a.tnix" (Text.pack report) `shouldBe` True
            Text.isInfixOf "- error src/b.tnix" (Text.pack report) `shouldBe` True
          Right output -> expectationFailure ("expected build failure, got: " <> Text.unpack output)
        doesFileExist (root </> "artifacts/a.nix") `shouldReturn` False
        doesFileExist (root </> "artifacts/types/a.d.tnix") `shouldReturn` False
        doesFileExist (root </> "artifacts/b.nix") `shouldReturn` False
        doesFileExist (root </> "artifacts/types/b.d.tnix") `shouldReturn` False

    it "does not write project declaration outputs when any source fails"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"demo\";",
                "  sourceDir = ./src;",
                "  generatedDeclarationDir = ./generated;",
                "}"
              ]
          ),
          ("src/a.tnix", "{ value = 1; }"),
          ("src/b.tnix", "missing")
        ]
      $ \root -> do
        result <- executeCommand (EmitProject (Just root) TextFormat)
        case result of
          Left report -> do
            Text.isInfixOf "- ok src/a.tnix" (Text.pack report) `shouldBe` True
            Text.isInfixOf "- error src/b.tnix" (Text.pack report) `shouldBe` True
          Right output -> expectationFailure ("expected emit-project failure, got: " <> Text.unpack output)
        doesFileExist (root </> "generated/a.d.tnix") `shouldReturn` False
        doesFileExist (root </> "generated/b.d.tnix") `shouldReturn` False

    it "emits project declarations as json"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"demo\";",
                "  sourceDir = ./src;",
                "}"
              ]
          ),
          ("src/main.tnix", "{ value = 1; }")
        ]
      $ \root -> do
        output <- executeCommand (EmitProject (Just root) JsonFormat) >>= expectRight
        Text.isInfixOf "\"schemaVersion\":1" output `shouldBe` True
        Text.isInfixOf "\"action\":\"emit-project\"" output `shouldBe` True
        Text.isInfixOf "\"success\":true" output `shouldBe` True

  describe "writeOutput" $
    it "creates parent directories before writing files" $
      withTempTree [] $ \root -> do
        let path = root <> "/dist/nested/out.txt"
        writeOutput (Just path) "hello"
        doesFileExist path `shouldReturn` True

  describe "check-project against pathological filesystems" $ do
    it "terminates on a directory symlink loop without hanging"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"loop\";",
                "  sourceDir = ./src;",
                "}"
              ]
          ),
          ("src/main.tnix", "1")
        ]
      $ \root -> do
        -- Create src/loop -> src so a naive walker would recurse forever.
        createDirectoryLink (root </> "src") (root </> "src/loop")
        result <-
          timeout
            (5 * 1000 * 1000)
            (executeCommand (CheckProject (Just root) TextFormat))
        case result of
          Just (Right report) ->
            Text.isInfixOf "ok src/main.tnix" report `shouldBe` True
          Just (Left err) ->
            expectationFailure ("expected ok, got error: " <> err)
          Nothing -> expectationFailure "check-project hung on symlink loop"

    it "stops walking when the directory depth exceeds the budget"
      $ withTempTree
        [ ( "tnix.config.tnix",
            source
              [ "{",
                "  name = \"deep\";",
                "  sourceDir = ./src;",
                "}"
              ]
          ),
          ("src/main.tnix", "1")
        ]
      $ \root -> do
        -- Create a deep nested layout below the configured source dir.
        let deep = root </> "src" </> deepPath 80
        createDirectoryIfMissing True deep
        TextIO.writeFile (deep </> "leaf.tnix") "1"
        result <- executeCommand (CheckProject (Just root) TextFormat)
        case result of
          Right report ->
            Text.isInfixOf "ok src/main.tnix" report `shouldBe` True
          Left err ->
            expectationFailure ("expected ok, got error: " <> err)
  where
    parserInfo = info commandParser mempty
    parserPrefs :: ParserPrefs
    parserPrefs = defaultPrefs
    parse = getParseResult . execParserPure parserPrefs parserInfo
    parserResult = execParserPure parserPrefs parserInfo

expectRight :: (Show e) => Either e a -> IO a
expectRight (Right value) = pure value
expectRight (Left err) = expectationFailure ("expected Right, got Left: " <> show err) >> fail "expected Right"

expectLeftContaining :: Either String a -> String -> Expectation
expectLeftContaining result needle =
  case result of
    Left err | Text.pack needle `Text.isInfixOf` Text.pack err -> pure ()
    Left err -> expectationFailure ("expected error containing " <> show needle <> ", got " <> show err)
    Right _ -> expectationFailure ("expected Left containing " <> show needle <> ", got Right")

source :: [Text] -> Text
source = Text.unlines

deepPath :: Int -> FilePath
deepPath n = intercalate "/" (replicate n "deep")

withTempTree :: [(FilePath, Text)] -> (FilePath -> IO a) -> IO a
withTempTree files action = bracket createRoot removePathForcibly (\root -> writeTree root >> action root)
  where
    createRoot = do
      tmp <- getTemporaryDirectory
      (path, handle) <- openTempFile tmp "tnix-cli-spec"
      hClose handle
      removeFile path
      createDirectory path
      pure path
    writeTree root =
      forM_ files $ \(relative, content) -> do
        let path = root </> relative
        createDirectoryIfMissing True (takeDirectory path)
        TextIO.writeFile path content
