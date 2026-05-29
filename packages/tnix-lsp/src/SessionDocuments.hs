{-# LANGUAGE OverloadedStrings #-}

-- | Document cache CRUD and the workspace document loader.
--
-- This module owns the in-memory @Documents@ map: how documents arrive
-- (didOpen / didChange), how they leave (didClose), and how a workspace
-- view is reconstructed for cross-file requests (`references`, `rename`,
-- workspace-wide `definition`).
--
-- Pure data types live in 'SessionTypes'; this module wires them to the
-- protocol handlers' incoming JSON messages.
module SessionDocuments
  ( -- * Cache CRUD
    closeDocuments,
    deleteDocument,
    insertDocument,
    lookupCachedDocument,
    lookupDocumentText,
    documentsFromList,
    updateDocuments,

    -- * Loading
    effectiveCachedAnalysis,
    loadDocumentAnalysis,
    loadDocumentContent,
    loadWorkspaceDocuments,

    -- * Workspace seed
    workspaceSeedFile,
  )
where

import Control.Monad (forM)
import Data.Aeson (Value)
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Driver (Analysis)
import Server
  ( applyContentChanges,
    asText,
    documentPath,
    field,
    uriPath,
  )
import SessionTypes
  ( CachedDocument (..),
    Documents (..),
    WorkspaceDocument (..),
  )
import SessionWorkspace (findBuiltinsFile, workspaceFilesFor)
import System.FilePath (normalise)

-- | Seed 'Documents' from an in-memory file list. Useful for tests.
documentsFromList :: [(FilePath, Text)] -> Documents
documentsFromList =
  Documents
    . Map.fromList
    . map
      ( \(file, text) ->
          ( normalise file,
            CachedDocument
              { cachedDocumentText = text,
                cachedDocumentAnalysis = Nothing,
                cachedDocumentLastGoodAnalysis = Nothing
              }
          )
      )

-- | Look up the cached buffer text for a file.
lookupDocumentText :: FilePath -> Documents -> Maybe Text
lookupDocumentText file (Documents docs) =
  cachedDocumentText <$> Map.lookup (normalise file) docs

-- | Look up the entire cached document (text + analysis).
lookupCachedDocument :: FilePath -> Documents -> Maybe CachedDocument
lookupCachedDocument file (Documents docs) = Map.lookup (normalise file) docs

-- | Insert or replace a document, preserving the previous "last good
-- analysis" when the new analysis fails. This is how the LSP keeps
-- showing useful hovers while the user is mid-edit.
insertDocument :: FilePath -> Text -> Maybe (Either String Analysis) -> Documents -> Documents
insertDocument file content analysis (Documents docs) =
  Documents
    ( Map.insert
        normalizedFile
        CachedDocument
          { cachedDocumentText = content,
            cachedDocumentAnalysis = analysis,
            cachedDocumentLastGoodAnalysis = newLastGood
          }
        docs
    )
  where
    normalizedFile = normalise file
    previousLastGood = cachedDocumentLastGoodAnalysis =<< Map.lookup normalizedFile docs
    newLastGood =
      case analysis of
        Just (Right result) -> Just result
        _ -> previousLastGood

-- | Remove a document from the cache.
deleteDocument :: FilePath -> Documents -> Documents
deleteDocument file (Documents docs) = Documents (Map.delete (normalise file) docs)

-- | Pick the analysis result a consumer should see for a cached document.
--
-- A successful current analysis wins; otherwise we fall back to the last
-- known good analysis so editor features keep working through transient
-- errors. The plain error string is only surfaced when there was never a
-- successful analysis for this file.
effectiveCachedAnalysis :: CachedDocument -> Maybe (Either String Analysis)
effectiveCachedAnalysis cached =
  case cachedDocumentAnalysis cached of
    Just (Right result) -> Just (Right result)
    Just (Left err) ->
      case cachedDocumentLastGoodAnalysis cached of
        Just result -> Just (Right result)
        Nothing -> Just (Left err)
    Nothing -> Nothing

-- | Update or open one document and re-run semantic analysis.
--
-- Full-text @didOpen@/@didChange@ updates replace the cached content
-- directly. Incremental @didChange@ messages reuse the cached buffer when
-- possible and fall back to reading from disk only when the editor has
-- not opened the file yet.
updateDocuments ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO (Documents, FilePath, Either String Analysis)
updateDocuments readDocument analyze docs msg = do
  let params = field "params" msg
      textDocument = params >>= field "textDocument"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
      fullText = textDocument >>= field "text" >>= asText
      current = lookupDocumentText file docs
  contentResult <-
    case fullText of
      Just content -> pure (Right content)
      Nothing -> do
        base <- maybe (readDocument file) (pure . Right) current
        pure (base >>= (`applyContentChanges` params))
  case contentResult of
    Left err -> pure (docs, file, Left err)
    Right content -> do
      result <- analyze file content
      pure (insertDocument file content (Just result) docs, file, result)

-- | Remove one document from the cache and return the cleared file path.
closeDocuments :: Documents -> Value -> (Documents, Maybe FilePath)
closeDocuments docs msg =
  case normalise <$> documentPath (field "params" msg) of
    Just file -> (deleteDocument file docs, Just file)
    Nothing -> (docs, Nothing)

-- | Fetch a document's current text, falling back to disk when the editor
-- has not opened the file yet.
loadDocumentContent :: (FilePath -> IO (Either String Text)) -> Documents -> FilePath -> IO (Either String Text)
loadDocumentContent readDocument docs file =
  maybe (readDocument file) (pure . Right) (lookupDocumentText file docs)

-- | Fetch a document's analysis, reusing the cached result when possible
-- and reading + re-analysing from disk otherwise.
loadDocumentAnalysis ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  FilePath ->
  IO (Either String Analysis)
loadDocumentAnalysis readDocument analyze docs file =
  case lookupCachedDocument file docs of
    Just cached ->
      case effectiveCachedAnalysis cached of
        Just result -> pure result
        Nothing -> analyze file (cachedDocumentText cached)
    Nothing -> do
      contentResult <- readDocument file
      case contentResult of
        Left err -> pure (Left err)
        Right content -> analyze file content

-- | Load every file in the workspace alongside the discovered
-- @builtins.d.tnix@ ambient declaration, reusing the cache where possible.
loadWorkspaceDocuments ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  FilePath ->
  IO [WorkspaceDocument]
loadWorkspaceDocuments readDocument analyze docs currentFile = do
  files <- workspaceFilesFor currentFile
  builtinsFile <- findBuiltinsFile currentFile
  let targets = nub (files <> maybe [] pure builtinsFile)
  forM targets $ \path -> do
    case lookupCachedDocument path docs of
      Just cached -> do
        result <-
          case effectiveCachedAnalysis cached of
            Just analysisResult -> pure analysisResult
            Nothing -> analyze path (cachedDocumentText cached)
        pure
          WorkspaceDocument
            { workspaceDocumentFile = path,
              workspaceDocumentContent = cachedDocumentText cached,
              workspaceDocumentAnalysis = result
            }
      Nothing -> do
        contentResult <- readDocument path
        case contentResult of
          Left err ->
            pure
              WorkspaceDocument
                { workspaceDocumentFile = path,
                  workspaceDocumentContent = "",
                  workspaceDocumentAnalysis = Left err
                }
          Right content -> do
            result <- analyze path content
            pure
              WorkspaceDocument
                { workspaceDocumentFile = path,
                  workspaceDocumentContent = content,
                  workspaceDocumentAnalysis = result
                }

-- | Pick a file to use as the workspace seed when the request did not
-- carry one (`workspace/symbol`).
workspaceSeedFile :: Documents -> Maybe FilePath
workspaceSeedFile (Documents docs) = fst <$> Map.lookupMin docs
