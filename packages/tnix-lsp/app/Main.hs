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
    accessAnalysisCache,
    emptyAnalysisCache,
    insertAnalysisCache,
  )
import Control.Exception (IOException, SomeException, fromException, throwIO, try)
import Data.Aeson
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (showVersion)
import Driver (Analysis (..), analyzeText)
import Paths_tnix_lsp qualified as PackageInfo
import Server (asText, clearDiagnostics, clientCapabilities, field, publishDiagnostics, publishDiagnosticsWithContent, respond, respondError)
import ServerProtocol (ReadOutcome (..), notify, readMessageOutcome)
import Session qualified
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitFailure, exitSuccess, exitWith)
import System.IO
  ( BufferMode (LineBuffering, NoBuffering),
    IOMode (AppendMode),
    hPutStrLn,
    hSetBinaryMode,
    hSetBuffering,
    openFile,
    stderr,
    stdin,
    stdout,
  )

-- | Start the stdio event loop and keep the latest document text in memory.
main :: IO ()
main = do
  args <- getArgs
  handleArgs args

handleArgs :: [String] -> IO ()
handleArgs args
  | any (`elem` ["--help", "-h"]) args = putStrLn helpText
  | any (`elem` ["--version", "-v"]) args = putStrLn versionText
  | otherwise = case parseServerArgs args of
      Left err -> do
        hPutStrLn stderr ("tnix-lsp: " <> err)
        hPutStrLn stderr "Use --stdio, --log-file PATH, --version, or --help."
        exitFailure
      Right logFile -> runServer logFile

-- | Parse the supported server flags. Recognizes @--stdio@ (the implicit
-- default) and an optional @--log-file PATH@ / @--log-file=PATH@; anything
-- else is rejected so typos do not silently start a misconfigured server.
parseServerArgs :: [String] -> Either String (Maybe FilePath)
parseServerArgs = go Nothing
  where
    go logFile [] = Right logFile
    go logFile ("--stdio" : rest) = go logFile rest
    go _ ("--log-file" : path : rest) = go (Just path) rest
    go _ ["--log-file"] = Left "--log-file requires a path argument"
    go _ (arg : rest)
      | Just path <- stripPrefix' "--log-file=" arg = go (Just path) rest
      | otherwise = Left ("unsupported argument: " <> arg)
    stripPrefix' prefix value =
      if prefix == take (length prefix) value
        then Just (drop (length prefix) value)
        else Nothing

-- | A logging sink. Diagnostics always reach stderr and, when @--log-file@ is
-- configured, are also appended to that file.
type Logger = Text -> IO ()

runServer :: Maybe FilePath -> IO ()
runServer logFile = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdin NoBuffering
  hSetBuffering stdout NoBuffering
  logHandle <- traverse openLogHandle logFile
  let logger = makeLogger logHandle
  ref <- newIORef mempty
  cacheRef <- newIORef emptyAnalysisCache
  shutdownRef <- newIORef False
  let analyze = cachedAnalyzeText cacheRef
      clearCache = writeIORef cacheRef emptyAnalysisCache
  loop logger shutdownRef ref analyze clearCache
  where
    openLogHandle path = do
      h <- openFile path AppendMode
      hSetBuffering h LineBuffering
      pure h
    makeLogger logHandle message = do
      hPutStrLn stderr ("tnix-lsp: " <> T.unpack message)
      case logHandle of
        Just h -> hPutStrLn h ("tnix-lsp: " <> T.unpack message)
        Nothing -> pure ()
    loop logger shutdownRef ref analyze clearCache = do
      outcome <- readMessageOutcome stdin
      case outcome of
        ReadEof -> pure ()
        ReadMessage msg ->
          safeHandle logger shutdownRef ref analyze clearCache msg >> loop logger shutdownRef ref analyze clearCache
        ReadError reason -> do
          logger reason
          loop logger shutdownRef ref analyze clearCache

-- | Run one handler, isolating crashes so a single bad document or a partial
-- function deep in the checker cannot take down the whole session.
--
-- 'ExitCode' (raised by @exit@/@shutdown@ handling) is re-thrown so the server
-- can still terminate; any other exception is logged, surfaced to the client
-- via @window/logMessage@, and—if the failing message was a request—answered
-- with a JSON-RPC internal error so the client is never left waiting.
safeHandle :: Logger -> IORef Bool -> IORef Session.Documents -> AnalyzeFn -> IO () -> Value -> IO ()
safeHandle logger shutdownRef ref analyze clearCache msg = do
  result <- try (handle shutdownRef ref analyze clearCache msg)
  case result of
    Right () -> pure ()
    Left err
      | Just code <- fromException err -> throwIO (code :: ExitCode)
      | otherwise -> do
          let detail = T.pack (show (err :: SomeException))
          logger ("handler error: " <> detail)
          notify
            stdout
            "window/logMessage"
            (object ["type" .= (1 :: Int), "message" .= ("tnix-lsp internal error: " <> detail)])
          case field "id" msg of
            Just _ -> respondError stdout msg (-32603) ("internal error: " <> detail)
            Nothing -> pure ()

-- | Wrap 'analyzeText' with the workspace-wide analysis cache so repeated
-- hover / workspace-symbol / definition requests against unchanged content
-- collapse to a single driver invocation.
cachedAnalyzeText :: IORef AnalysisCache -> FilePath -> Text -> IO (Either String Analysis)
cachedAnalyzeText cacheRef file content = do
  cache <- readIORef cacheRef
  case accessAnalysisCache (file, content) cache of
    (Just result, touchedCache) -> do
      writeIORef cacheRef touchedCache
      pure result
    (Nothing, _) -> do
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
handle :: IORef Bool -> IORef Session.Documents -> AnalyzeFn -> IO () -> Value -> IO ()
handle shutdownRef ref analyze clearCache msg = case field "method" msg >>= asText of
  Just "initialize" -> respond stdout msg clientCapabilities
  Just "initialized" -> pure ()
  Just "shutdown" -> writeIORef shutdownRef True >> respond stdout msg Null
  -- Per the LSP spec, `exit` returns code 0 only when a `shutdown` request
  -- preceded it, and 1 otherwise.
  Just "exit" -> do
    didShutdown <- readIORef shutdownRef
    if didShutdown then exitSuccess else exitWith (ExitFailure 1)
  -- Requests are processed synchronously, so by the time a cancellation
  -- arrives its target has already been answered; acknowledge and ignore.
  Just "$/cancelRequest" -> pure ()
  Just "textDocument/didOpen" -> update ref analyze msg >>= publish
  Just "textDocument/didChange" -> update ref analyze msg >>= publish
  Just "textDocument/didSave" -> update ref analyze msg >>= publish
  Just "textDocument/didClose" -> closeDocument ref msg
  Just "textDocument/hover" -> hover ref analyze msg >>= respond stdout msg
  Just "textDocument/signatureHelp" -> signatureHelp ref analyze msg >>= respond stdout msg
  Just "textDocument/completion" -> completion ref analyze msg >>= respond stdout msg
  Just "textDocument/definition" -> definition ref analyze msg >>= respond stdout msg
  Just "textDocument/declaration" -> definition ref analyze msg >>= respond stdout msg
  Just "textDocument/references" -> references ref analyze msg >>= respond stdout msg
  Just "textDocument/documentHighlight" -> documentHighlights ref analyze msg >>= respond stdout msg
  Just "textDocument/rename" -> rename ref analyze msg >>= respond stdout msg
  Just "textDocument/documentSymbol" -> documentSymbols ref analyze msg >>= respond stdout msg
  Just "workspace/symbol" -> workspaceSymbols ref analyze msg >>= respond stdout msg
  Just "textDocument/codeAction" -> codeActions ref analyze msg >>= respond stdout msg
  Just "textDocument/semanticTokens/full" -> semanticTokens ref analyze msg >>= respond stdout msg
  Just "textDocument/foldingRange" -> foldingRanges ref msg >>= respond stdout msg
  Just "textDocument/documentLink" -> documentLinks ref msg >>= respond stdout msg
  Just "textDocument/inlayHint" -> inlayHints ref analyze msg >>= respond stdout msg
  Just "workspace/didChangeWatchedFiles" -> clearCache
  Just "workspace/didChangeConfiguration" -> clearCache
  -- A request (carries an `id`) for a method we do not implement must be
  -- answered with MethodNotFound; unknown notifications are ignored.
  method -> case field "id" msg of
    Just _ ->
      respondError
        stdout
        msg
        (-32601)
        (maybe "method not found" ("method not found: " <>) method)
    Nothing -> pure ()

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

-- | Compute signature help at the requested position.
signatureHelp :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
signatureHelp ref analyze msg = do
  docs <- readIORef ref
  Session.signatureHelpDocument readFileSafe analyze docs msg

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

documentHighlights :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
documentHighlights ref analyze msg = do
  docs <- readIORef ref
  Session.documentHighlightsDocument readFileSafe analyze docs msg

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

foldingRanges :: IORef Session.Documents -> Value -> IO Value
foldingRanges ref msg = do
  docs <- readIORef ref
  Session.foldingRangesDocument readFileSafe docs msg

documentLinks :: IORef Session.Documents -> Value -> IO Value
documentLinks ref msg = do
  docs <- readIORef ref
  Session.documentLinksDocument readFileSafe docs msg

inlayHints :: IORef Session.Documents -> AnalyzeFn -> Value -> IO Value
inlayHints ref analyze msg = do
  docs <- readIORef ref
  Session.inlayHintsDocument readFileSafe analyze docs msg

readFileSafe :: FilePath -> IO (Either String Text)
readFileSafe file = do
  result <- try @IOException (TIO.readFile file)
  pure $
    case result of
      Left err -> Left ("failed to read " <> file <> ": " <> show err)
      Right content -> Right content
