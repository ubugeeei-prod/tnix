{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | High-level entry points that stitch parsing, checking, compilation, ambient
-- declaration discovery, and emission together.
--
-- The rest of the repo treats this module as the main service layer. CLI
-- commands call it directly, the LSP keeps analyzed results from it in memory,
-- and tests use it to exercise end-to-end behavior.
module Driver
  ( Analysis (..),
    SupportCache,
    analyzeFile,
    analyzeFileWith,
    analyzeText,
    analyzeTextWith,
    compileFile,
    compileFileWith,
    compileText,
    emitFileAs,
    emitFileAsWith,
    emitFile,
    emitFileTo,
    emitText,
    emitTextAs,
    emitTextTo,
    lookupSymbolType,
    newSupportCache,
    parseText,
  )
where

import Alias
import Check hiding (resolvePath)
import Check qualified
import Compile
import Control.Applicative ((<|>))
import Control.Exception (IOException, displayException, try)
import Control.Monad (foldM, forM)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (group, isSuffixOf, nub, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Diagnostics (DiagnosticCode (..), withCode)
import Emit
import Indexed
import Kind
import Parser
import Pretty (renderExpr)
import Syntax
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (isAbsolute, joinPath, normalise, replaceExtension, splitDirectories, takeDirectory, (</>))
import Type

-- | End-to-end analysis result for one file.
--
-- Keeping the parsed program alongside inferred schemes lets downstream tools
-- answer both syntactic and semantic questions without reparsing.
data Analysis = Analysis
  { analysisProgram :: Program,
    analysisRoot :: Maybe Scheme,
    analysisBindings :: Map Name Scheme,
    analysisAliases :: AliasEnv,
    analysisAmbient :: Map FilePath Scheme
  }
  deriving (Eq, Show)

-- | Parse a source buffer and normalize parser errors to plain strings.
parseText :: FilePath -> Text -> Either String Program
parseText path = either (Left . Text.unpack) Right . parseProgram path

-- | Analyze an in-memory source buffer, loading nearby declaration support.
analyzeText :: FilePath -> Text -> IO (Either String Analysis)
analyzeText path input = newSupportCache >>= \cache -> analyzeTextWith cache path input

-- | 'analyzeText' reusing declaration support already loaded into @cache@.
analyzeTextWith :: SupportCache -> FilePath -> Text -> IO (Either String Analysis)
analyzeTextWith cache path input = do
  support <- loadSupportWith cache path
  pure $ do
    supportWorld <- support
    program <- parseText path input
    _ <- validateProgramKinds (programAliases program <> worldAliases supportWorld) program
    _ <- validateProgramIndexedTypes program
    localAmbient <- collectAmbient path program
    let aliases = mkAliasEnv (programAliases program <> worldAliases supportWorld)
        ambient = localAmbient <> worldAmbient supportWorld
        context = CheckContext{checkAliases = aliases, checkAmbient = ambient, checkFile = path, checkOpenScope = False}
    result <- checkProgram context program
    pure
      Analysis
        { analysisProgram = program,
          analysisRoot = resultRoot result,
          analysisBindings = resultBindings result,
          analysisAliases = aliases,
          analysisAmbient = ambient
        }

-- | Read and analyze a file from disk.
analyzeFile :: FilePath -> IO (Either String Analysis)
analyzeFile path = newSupportCache >>= \cache -> analyzeFileWith cache path

-- | 'analyzeFile' reusing declaration support already loaded into @cache@.
analyzeFileWith :: SupportCache -> FilePath -> IO (Either String Analysis)
analyzeFileWith cache path = readTextFile path >>= either (pure . Left) (analyzeTextWith cache path)

-- | Compile an in-memory `.tnix` buffer into `.nix` text.
compileText :: FilePath -> Text -> IO (Either String Text)
compileText path input = newSupportCache >>= \cache -> compileTextWith cache path input

compileTextWith :: SupportCache -> FilePath -> Text -> IO (Either String Text)
compileTextWith cache path input = do
  checked <- analyzeTextWith cache path input
  pure $ checked >>= \analysis -> either (Left . Text.unpack) Right (compileProgram (analysisProgram analysis))

-- | Compile a file from disk.
compileFile :: FilePath -> IO (Either String Text)
compileFile path = newSupportCache >>= \cache -> compileFileWith cache path

-- | 'compileFile' reusing declaration support already loaded into @cache@.
compileFileWith :: SupportCache -> FilePath -> IO (Either String Text)
compileFileWith cache path = readTextFile path >>= either (pure . Left) (compileTextWith cache path)

-- | Emit a declaration file for an in-memory source buffer.
emitText :: FilePath -> Text -> IO (Either String Text)
emitText path input = do
  checked <- analyzeText path input
  pure $ do
    analysis <- checked
    root <- maybe (Left (withCode TD0008DeclarationOnlyEmit "cannot emit declarations from a declaration-only file")) Right (analysisRoot analysis)
    pure (emitDeclarationFile path (analysisProgram analysis) root)

emitTextTo :: FilePath -> FilePath -> Text -> IO (Either String Text)
emitTextTo source declarationPath input = do
  let runtimeTarget = replaceExtension source "nix"
  emitTextAs source runtimeTarget declarationPath input

emitTextAs :: FilePath -> FilePath -> FilePath -> Text -> IO (Either String Text)
emitTextAs source runtimeTarget declarationPath input =
  newSupportCache >>= \cache -> emitTextAsWith cache source runtimeTarget declarationPath input

emitTextAsWith :: SupportCache -> FilePath -> FilePath -> FilePath -> Text -> IO (Either String Text)
emitTextAsWith cache source runtimeTarget declarationPath input = do
  checked <- analyzeTextWith cache source input
  pure $ do
    analysis <- checked
    root <- maybe (Left (withCode TD0008DeclarationOnlyEmit "cannot emit declarations from a declaration-only file")) Right (analysisRoot analysis)
    pure (emitDeclarationFileFor runtimeTarget declarationPath (analysisProgram analysis) root)

-- | Emit a declaration file for a source file on disk.
emitFile :: FilePath -> IO (Either String Text)
emitFile path = readTextFile path >>= either (pure . Left) (emitText path)

emitFileTo :: FilePath -> FilePath -> IO (Either String Text)
emitFileTo source declarationPath = readTextFile source >>= either (pure . Left) (emitTextTo source declarationPath)

emitFileAs :: FilePath -> FilePath -> FilePath -> IO (Either String Text)
emitFileAs source runtimeTarget declarationPath =
  newSupportCache >>= \cache -> emitFileAsWith cache source runtimeTarget declarationPath

-- | 'emitFileAs' reusing declaration support already loaded into @cache@.
emitFileAsWith :: SupportCache -> FilePath -> FilePath -> FilePath -> IO (Either String Text)
emitFileAsWith cache source runtimeTarget declarationPath =
  readTextFile source >>= either (pure . Left) (emitTextAsWith cache source runtimeTarget declarationPath)

-- | Look up a top-level symbol type exposed by an analysis result.
--
-- `default` is synthesized from the root expression so editor tooling can show
-- something useful even when the file does not bind a name explicitly.
lookupSymbolType :: Analysis -> Name -> Maybe Scheme
lookupSymbolType analysis name =
  Map.lookup name (analysisBindings analysis)
    <|> (analysisRoot analysis >>= \root -> if name == "default" then Just root else Nothing)

data World = World
  { worldAliases :: [TypeAlias],
    worldAmbient :: Map FilePath Scheme
  }

data DeclarationSupportFile = DeclarationSupportFile
  { declarationLoadPath :: FilePath,
    declarationResolvePath :: FilePath
  }
  deriving (Eq, Ord, Show)

builtinsAmbientKey :: FilePath
builtinsAmbientKey = "builtins"

-- | Declaration support discovered for one workspace root.
--
-- Discovery, reading, and parsing depend only on the root, so the expensive
-- part is shared by every source file under it. Only the final filter — a
-- declaration file never contributes support to itself — is per-source, and
-- that is cheap enough to redo.
data SupportBundle = SupportBundle
  { bundleFiles :: [DeclarationSupportFile],
    bundleWorlds :: [Either String World]
  }

-- | Memo table for 'SupportBundle's, keyed by workspace root.
--
-- Without it, analyzing @n@ sources against @m@ declaration files re-walks the
-- workspace and re-parses every declaration file @n@ times. Callers that
-- analyze more than one file — @check-project@, @build@, @emit-project@, and
-- the language server's workspace-wide requests — should create one cache and
-- thread it through, which collapses that to a single pass.
--
-- The cache holds no invalidation logic on purpose: its scope is one CLI
-- command or one LSP request, so it can never serve a stale read.
newtype SupportCache = SupportCache (IORef (Map FilePath (Either String SupportBundle)))

-- | Create an empty 'SupportCache'.
newSupportCache :: IO SupportCache
newSupportCache = SupportCache <$> newIORef Map.empty

loadSupportWith :: SupportCache -> FilePath -> IO (Either String World)
loadSupportWith (SupportCache ref) path = do
  root <- findSupportRoot path
  cached <- Map.lookup root <$> readIORef ref
  bundle <- case cached of
    Just hit -> pure hit
    Nothing -> do
      loaded <- loadSupportBundle root
      modifyIORef' ref (Map.insert root loaded)
      pure loaded
  pure (bundle >>= supportWorldFor path)

loadSupportBundle :: FilePath -> IO (Either String SupportBundle)
loadSupportBundle root = do
  exists <- doesDirectoryExist root
  if not exists
    then pure (Right (SupportBundle [] []))
    else do
      workspaceFiles <- map (\file -> DeclarationSupportFile file file) <$> findWorkspaceDeclarationFiles root
      configuredFilesResult <- loadConfiguredDeclarationFiles root
      case configuredFilesResult of
        Left err -> pure (Left err)
        Right configuredFiles -> do
          let declarationFiles = dedupeDeclarationFiles (workspaceFiles <> configuredFiles)
          worlds <- traverse loadDeclarationFile declarationFiles
          pure (Right (SupportBundle declarationFiles worlds))

-- | Assemble the world visible from @source@, dropping the entry for the file
-- being analyzed so a declaration file never declares itself.
supportWorldFor :: FilePath -> SupportBundle -> Either String World
supportWorldFor source bundle = do
  let kept =
        filter
          ((/= normalise source) . declarationLoadPath . fst)
          (zip (bundleFiles bundle) (bundleWorlds bundle))
  loaded <- traverse snd kept
  mergeLoadedWorlds (map fst kept) loaded

dedupeDeclarationFiles :: [DeclarationSupportFile] -> [DeclarationSupportFile]
dedupeDeclarationFiles =
  nub
    . sort
    . map normalizeDeclarationSupportFile

normalizeDeclarationSupportFile :: DeclarationSupportFile -> DeclarationSupportFile
normalizeDeclarationSupportFile file =
  file
    { declarationLoadPath = normalise (declarationLoadPath file),
      declarationResolvePath = normalise (declarationResolvePath file)
    }

loadConfiguredDeclarationFiles :: FilePath -> IO (Either String [DeclarationSupportFile])
loadConfiguredDeclarationFiles root = do
  let configPath = root </> "tnix.config.tnix"
  exists <- doesFileExist configPath
  if not exists
    then pure (Right [])
    else do
      inputResult <- readTextFile configPath
      case inputResult of
        Left err -> pure (Left err)
        Right input ->
          case parseText configPath input of
            Left err -> pure (Left (withCode TD0004ConfigDecodeError ("failed to parse " <> configPath <> ": " <> err)))
            Right program ->
              case configuredDeclarationPackPaths configPath program of
                Left err -> pure (Left err)
                Right packs -> do
                  expanded <- traverse (expandDeclarationPackPath root) packs
                  pure (fmap concat (sequence expanded))

configuredDeclarationPackPaths :: FilePath -> Program -> Either String [FilePath]
configuredDeclarationPackPaths configPath program = do
  expr <- maybe (Left (withCode TD0004ConfigDecodeError ("tnix.config.tnix must contain a root attribute set: " <> configPath))) (Right . markedValue) (programExpr program)
  decodeDeclarationPackField (takeDirectory configPath) expr

decodeDeclarationPackField :: FilePath -> Expr -> Either String [FilePath]
decodeDeclarationPackField root = \case
  EAttrSet items ->
    case [expr | AttrField "declarationPacks" expr <- items] of
      [] -> Right []
      [expr] -> decodePathList root "declarationPacks" expr
      _ -> Left (withCode TD0004ConfigDecodeError "duplicate config field: declarationPacks")
  _ -> Left (withCode TD0004ConfigDecodeError "tnix.config.tnix must evaluate to an attrset")

decodePathList :: FilePath -> Text -> Expr -> Either String [FilePath]
decodePathList root label = \case
  EList items -> traverse decodeItem items
  other -> Left (withCode TD0005ConfigBadList ("expected list of path-like values for " <> Text.unpack label <> ", but got " <> Text.unpack (renderExpr other)))
  where
    decodeItem = \case
      EPath path -> Right (resolveConfigPath root path)
      EString text -> Right (resolveConfigPath root (Text.unpack (stringLiteralText text)))
      item -> Left (withCode TD0006ConfigBadItem ("expected path-like item in " <> Text.unpack label <> ", but got " <> Text.unpack (renderExpr item)))

expandDeclarationPackPath :: FilePath -> FilePath -> IO (Either String [DeclarationSupportFile])
expandDeclarationPackPath root path = do
  let normalized = normalise path
  isDir <- doesDirectoryExist normalized
  fileExists <- doesFileExist normalized
  if isDir
    then do
      files <- findDeclarationFiles normalized
      pure (Right (map (mkDeclarationSupportFile root) files))
    else
      if fileExists
        then
          if ".d.tnix" `isSuffixOf` normalized
            then pure (Right [mkDeclarationSupportFile root normalized])
            else pure (Left (withCode TD0006ConfigBadItem ("declarationPacks entries must point to .d.tnix files or directories, but got " <> normalized)))
        else pure (Left (withCode TD0006ConfigBadItem ("declarationPacks entry does not exist: " <> normalized)))

mkDeclarationSupportFile :: FilePath -> FilePath -> DeclarationSupportFile
mkDeclarationSupportFile root loadPath =
  DeclarationSupportFile
    { declarationLoadPath = loadPath,
      declarationResolvePath = maybe (normalise loadPath) (normalise . (root </>) . joinPath) (workspacePackRelativeParts loadPath)
    }

workspacePackRelativeParts :: FilePath -> Maybe [FilePath]
workspacePackRelativeParts path =
  findWorkspacePackSuffix (splitDirectories (normalise path))
  where
    findWorkspacePackSuffix ("registry" : "workspace" : rest) = Just ("registry" : "workspace" : rest)
    findWorkspacePackSuffix (_ : rest) = findWorkspacePackSuffix rest
    findWorkspacePackSuffix [] = Nothing

resolveConfigPath :: FilePath -> FilePath -> FilePath
resolveConfigPath root target
  | isAbsolute target = normalise target
  | otherwise = normalise (root </> dropDotSlash target)

dropDotSlash :: FilePath -> FilePath
dropDotSlash path =
  case path of
    '.' : '/' : rest -> rest
    _ -> path

mergeLoadedWorlds :: [DeclarationSupportFile] -> [World] -> Either String World
mergeLoadedWorlds files loaded = do
  ambient <- mergeAmbientWorlds (zip (map declarationLoadPath files) (map worldAmbient loaded))
  pure World{worldAliases = concatMap worldAliases loaded, worldAmbient = ambient}

loadDeclarationFile :: DeclarationSupportFile -> IO (Either String World)
loadDeclarationFile file = do
  let path = declarationLoadPath file
  inputResult <- readTextFile path
  pure $ do
    input <- inputResult
    program <- firstError ("failed to load declaration file " <> path <> ": ") (parseText path input)
    case markedValue <$> programExpr program of
      Just _ -> Left (withCode TD0007DeclarationOnlyCompile ("declaration files must not contain executable expressions: " <> path))
      Nothing -> do
        _ <- validateProgramKinds (programAliases program) program
        _ <- validateProgramIndexedTypes program
        ambient <- collectAmbientWithBase path (declarationResolvePath file) program
        pure World{worldAliases = programAliases program, worldAmbient = ambient}

collectAmbient :: FilePath -> Program -> Either String (Map FilePath Scheme)
collectAmbient file = collectAmbientWithBase file file

collectAmbientWithBase :: FilePath -> FilePath -> Program -> Either String (Map FilePath Scheme)
collectAmbientWithBase file resolveBase program = do
  let duplicates = duplicateNames (map (resolvePath resolveBase . ambientPath) (programAmbient program))
  case duplicates of
    dup : _ -> Left (withCode TD0002DuplicateAmbientDeclaration ("duplicate ambient declarations for target `" <> dup <> "` in " <> file))
    [] -> Map.fromList <$> traverse toPair (programAmbient program)
  where
    toPair decl = do
      scheme <- schemeFromEntries (ambientEntries decl)
      pure (resolvePath resolveBase (ambientPath decl), scheme)
    schemeFromEntries entries =
      case duplicateNames (map ambientEntryName entries) of
        dup : _ -> Left (withCode TD0003DuplicateAmbientEntry ("duplicate ambient entry `" <> Text.unpack dup <> "` in " <> file))
        [] ->
          Right $
            case entries of
              [AmbientEntry "default" ty] -> schemeFromAnnotation ty
              _ -> Scheme [] (TRecord (Map.fromList [(ambientEntryName entry, ambientEntryType entry) | entry <- entries]))

findDeclarationFiles :: FilePath -> IO [FilePath]
findDeclarationFiles dir = do
  names <- sort <$> listDirectory dir
  fmap concat $
    forM names $ \name -> do
      let path = dir </> name
      isDir <- doesDirectoryExist path
      if isDir
        then findDeclarationFiles path
        else pure [normalise path | ".d.tnix" `isSuffixOf` name]

findWorkspaceDeclarationFiles :: FilePath -> IO [FilePath]
findWorkspaceDeclarationFiles root = go root
  where
    go dir = do
      names <- sort <$> listDirectory dir
      fmap concat $
        forM names $ \name -> do
          let path = dir </> name
          isDir <- doesDirectoryExist path
          if isDir
            then do
              nestedWorkspace <- if normalise path == normalise root then pure False else hasWorkspaceMarker path
              if nestedWorkspace
                then pure []
                else go path
            else pure [normalise path | ".d.tnix" `isSuffixOf` name]

-- | Resolve an ambient declaration target.
--
-- Import resolution must agree exactly with the checker, so this delegates to
-- 'Check.resolvePath' rather than keeping a second copy of the same rules. The
-- one addition is the synthetic `builtins` target, which names the ambient
-- world rather than a file on disk.
resolvePath :: FilePath -> FilePath -> FilePath
resolvePath _ "builtins" = builtinsAmbientKey
resolvePath from target = Check.resolvePath from target

findSupportRoot :: FilePath -> IO FilePath
findSupportRoot path = go start
  where
    start = normalise (takeDirectory path)
    go dir = do
      marked <- hasWorkspaceMarker dir
      let parent = normalise (takeDirectory dir)
      if marked
        then pure dir
        else
          if parent == dir
            then pure start
            else go parent

hasWorkspaceMarker :: FilePath -> IO Bool
hasWorkspaceMarker dir =
  or
    <$> sequence
      [ doesFileExist (dir </> "flake.nix"),
        doesFileExist (dir </> "cabal.project"),
        doesFileExist (dir </> "pnpm-workspace.yaml"),
        doesFileExist (dir </> "tnix.config.tnix"),
        doesDirectoryExist (dir </> ".git")
      ]

mergeAmbientWorlds :: [(FilePath, Map FilePath Scheme)] -> Either String (Map FilePath Scheme)
mergeAmbientWorlds = fmap snd . foldM step (Map.empty, Map.empty)
  where
    step (sources, ambient) (file, additions) =
      foldM (insertOne file) (sources, ambient) (Map.toList additions)
    insertOne file (sources, ambient) (target, scheme) =
      case Map.lookup target sources of
        Just firstSource ->
          Left
            ( withCode
                TD0002DuplicateAmbientDeclaration
                ( "duplicate ambient declarations for target "
                    <> show target
                    <> " in "
                    <> firstSource
                    <> " and "
                    <> file
                )
            )
        Nothing ->
          Right (Map.insert target file sources, Map.insert target scheme ambient)

duplicateNames :: (Ord a) => [a] -> [a]
duplicateNames = foldr step [] . group . sort
  where
    step xs acc =
      case xs of
        first : _ | length xs > 1 -> first : acc
        _ -> acc

firstError :: String -> Either String a -> Either String a
firstError prefix = either (Left . (prefix <>)) Right

readTextFile :: FilePath -> IO (Either String Text)
readTextFile path = do
  result <- try @IOException (Text.readFile path)
  pure $
    case result of
      Left err -> Left (withCode TD0001ReadFailed ("failed to read " <> path <> ": " <> displayException err))
      Right input -> Right input
