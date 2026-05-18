{-# LANGUAGE OverloadedStrings #-}

-- | JSON-RPC/LSP bridge for tnix.
--
-- The server keeps protocol framing and stdio orchestration here while pushing
-- semantic behavior into the core driver and the testable 'Session' helpers.
-- That makes hover, diagnostics, completion, and jump-to-definition available
-- to real editors without burying the logic inside an opaque event loop.
module Main (main) where

import AnalysisCache
  ( AnalysisCache,
    emptyAnalysisCache,
    insertAnalysisCache,
    lookupAnalysisCache,
  )
import Control.Exception (IOException, try)
import Data.Aeson
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (showVersion)
import Driver (Analysis (..), analyzeText)
import Paths_tnix_lsp qualified as PackageInfo
import Server (ReadOutcome (..), asText, clearDiagnostics, clientCapabilities, field, notify, publishDiagnostics, publishDiagnosticsWithContent, readMessageOutcome, respond)
import Session qualified
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (BufferMode (NoBuffering), hPutStrLn, hSetBinaryMode, hSetBuffering, stderr, stdin, stdout)

-- | Start the stdio event loop and keep the latest document text in memory.
main :: IO ()
main = do
  args <- getArgs
  handleArgs args

handleArgs :: [String] -> IO ()
handleArgs args
  | any (`elem` ["--help", "-h"]) args = putStrLn helpText
  | any (`elem` ["--version", "-v"]) args = putStrLn versionText
  | null filteredArgs = runServer
  | otherwise = do
      hPutStrLn stderr ("tnix-lsp: unsupported arguments: " <> unwords filteredArgs)
      hPutStrLn stderr "Use --stdio, --version, or --help."
      exitFailure
  where
    filteredArgs = filter (/= "--stdio") args

runServer :: IO ()
runServer = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdin NoBuffering
  hSetBuffering stdout NoBuffering
  ref <- newIORef mempty
  cacheRef <- newIORef emptyAnalysisCache
  let analyze = cachedAnalyzeText cacheRef
  loop ref analyze
 where
  loop ref analyze = do
    outcome <- readMessageOutcome stdin
    case outcome of
      ReadEof -> pure ()
      ReadMessage msg -> handle ref analyze msg >> loop ref analyze
      ReadError reason -> do
        hPutStrLn stderr ("tnix-lsp: " <> T.unpack reason)
        loop ref analyze

-- | Wrap 'analyzeText' with the workspace-wide analysis cache so repeated
-- hover / workspace-symbol / definition requests against unchanged content
-- collapse to a single driver invocation.
cachedAnalyzeText :: IORef AnalysisCache -> FilePath -> Text -> IO (Either String Analysis)
cachedAnalyzeText cacheRef file content = do
  cache <- readIORef cacheRef
  case lookupAnalysisCache (file, content) cache of
    Just result -> pure result
    Nothing -> do
      result <- analyzeText file content
      modifyIORef' cacheRef (insertAnalysisCache (file, content) result)
      pure result

helpText :: String
helpText =
  unlines
    [ "tnix-lsp",
      "",
      "Usage:",
      "  tnix-lsp [--stdio]",
      "  tnix-lsp --version",
      "  tnix-lsp --help"
    ]

versionText :: String
versionText = "tnix-lsp " <> showVersion PackageInfo.version

-- | Type alias for the cached analyzer threaded through every handler.
type AnalyzeFn = FilePath -> Text -> IO (Either String Analysis)

-- | Dispatch one incoming JSON-RPC message.
handle :: IORef Session.Documents -> AnalyzeFn -> Value -> IO ()
handle ref analyze msg = case field "method" msg >>= asText of
  Just "initialize" -> respond stdout msg clientCapabilities
  Just "shutdown" -> respond stdout msg Null
  Just "exit" -> exitSuccess
  Just "textDocument/didOpen" -> update ref analyze msg >>= publish
  Just "textDocument/didChange" -> update ref analyze msg >>= publish
  Just "textDocument/didSave" -> update ref analyze msg >>= publish
  Just "textDocument/didClose" -> closeDocument ref msg
  Just "textDocument/hover" -> hover ref analyze msg >>= respond stdout msg
  Just "textDocument/completion" -> completion ref analyze msg >>= respond stdout msg
  Just "textDocument/definition" -> definition ref analyze msg >>= respond stdout msg
  Just "textDocument/declaration" -> definition ref analyze msg >>= respond stdout msg
  Just "textDocument/references" -> references ref analyze msg >>= respond stdout msg
  Just "textDocument/rename" -> rename ref analyze msg >>= respond stdout msg
  Just "textDocument/documentSymbol" -> documentSymbols ref analyze msg >>= respond stdout msg
  Just "workspace/symbol" -> workspaceSymbols ref analyze msg >>= respond stdout msg
  Just "textDocument/codeAction" -> codeActions ref analyze msg >>= respond stdout msg
  Just "textDocument/semanticTokens/full" -> semanticTokens ref analyze msg >>= respond stdout msg
  _ -> pure ()

-- | Update the in-memory copy of a document and re-run analysis.
update :: IORef Session.Documents -> AnalyzeFn -> Value -> IO (FilePath, Maybe Text, Either String Analysis)
update ref analyze msg = do
  docs <- readIORef ref
  (docs', file, result) <- Session.updateDocuments readFileSafe analyze docs msg
  writeIORef ref docs'
  pure (file, Session.lookupDocumentText file docs', result)

-- | Publish diagnostics for the latest analysis result.
publish :: (FilePath, Maybe Text, Either String Analysis) -> IO ()
publish (file, content, result) =
  notify
    stdout
    "textDocument/publishDiagnostics"
    (maybe (publishDiagnostics file result) (\text -> publishDiagnosticsWithContent file text result) content)

-- | Drop a document from the in-memory cache and clear its diagnostics.
closeDocument :: IORef Session.Documents -> Value -> IO ()
closeDocument ref msg = do
  docs <- readIORef ref
  let (docs', closed) = Session.closeDocuments docs msg
  writeIORef ref docs'
  case closed of
    Just file -> notify stdout "textDocument/publishDiagnostics" (clearDiagnostics file)
    Nothing -> pure ()

-- | Compute hover contents at the requested position.
hover :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
hover ref analyze msg = do
  docs <- readIORef ref
  Session.hoverDocument readFileSafe analyze docs msg

-- | Compute completion results at the requested position.
completion :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
completion ref analyze msg = do
  docs <- readIORef ref
  Session.completionDocument readFileSafe analyze docs msg

-- | Resolve local or ambient definitions for the requested position.
definition :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
definition ref analyze msg = do
  docs <- readIORef ref
  Session.definitionDocument readFileSafe analyze docs msg

references :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
references ref analyze msg = do
  docs <- readIORef ref
  Session.referencesDocument readFileSafe analyze docs msg

rename :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
rename ref analyze msg = do
  docs <- readIORef ref
  Session.renameDocument readFileSafe analyze docs msg

documentSymbols :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
documentSymbols ref analyze msg = do
  docs <- readIORef ref
  Session.documentSymbolsDocument readFileSafe analyze docs msg

workspaceSymbols :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
workspaceSymbols ref analyze msg = do
  docs <- readIORef ref
  Session.workspaceSymbolsDocument readFileSafe analyze docs msg

codeActions :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
codeActions ref analyze msg = do
  docs <- readIORef ref
  Session.codeActionsDocument readFileSafe analyze docs msg

semanticTokens :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
semanticTokens ref analyze msg = do
  docs <- readIORef ref
  Session.semanticTokensDocument readFileSafe analyze docs msg

readFileSafe :: FilePath -> IO (Either String Text)
readFileSafe file = do
  result <- try @IOException (TIO.readFile file)
  pure $
    case result of
      Left err -> Left ("failed to read " <> file <> ": " <> show err)
      Right content -> Right content
