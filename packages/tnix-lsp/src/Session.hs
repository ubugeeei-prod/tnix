{-# LANGUAGE OverloadedStrings #-}

-- | Testable document-session helpers for the tnix language server.
--
-- The executable keeps only the stdio loop and an 'IORef' cache. All document
-- lifecycle behavior lives here so specs can exercise the same update/hover
-- logic that the real server uses.
module Session
  ( Documents,
    closeDocuments,
    codeActionsDocument,
    completionDocument,
    definitionDocument,
    documentHighlightsDocument,
    documentLinksDocument,
    documentsFromList,
    documentSymbolsDocument,
    foldingRangesDocument,
    hoverDocument,
    inlayHintsDocument,
    lookupDocumentText,
    referencesDocument,
    renameDocument,
    semanticTokensDocument,
    updateDocuments,
    workspaceSymbolsDocument,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (forM)
import Data.Aeson (Value (..), object, toJSON, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Char (isAlphaNum, isDigit, isLetter, isUpper, toLower)
import Data.List (isSuffixOf, nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Driver (Analysis (..))
import Server
  ( applyContentChanges,
    asInt,
    asText,
    completionResult,
    documentHighlight,
    documentPath,
    field,
    findDefinitionRange,
    findFieldRange,
    hoverResult,
    location,
    pathUri,
    textOffsetToUtf16Column,
    textRangeToUtf16Columns,
    uriPath,
    wordAt,
  )
import SessionDiagnostics
  ( closestCandidate,
    diagnosticPayloads,
    diagnosticRange,
    diagnosticSymbolName,
    directiveActions,
    quickFixAction,
    textEdit,
    workspaceEdit,
  )
import SessionDocuments
  ( closeDocuments,
    documentsFromList,
    loadDocumentAnalysis,
    loadDocumentContent,
    loadWorkspaceDocuments,
    lookupDocumentText,
    updateDocuments,
    workspaceSeedFile,
  )
import SessionFolding (encodeFoldingRanges, foldingRangesFor)
import SessionInlayHints (encodeInlayHints, inlayHintsFor)
import SessionLinks (encodeDocumentLinks, findDocumentLinks)
import SessionReferences
  ( resolveDefinitionLocation,
    resolveReferenceTarget,
    symbolRanges,
    workspaceDocumentsForTarget,
  )
import SessionSemanticTokens (encodeSemanticTokens, semanticTokensFor)
import SessionSymbols
  ( documentCandidateNames,
    documentIndexedSymbols,
    findDeclareRange,
    indexedSymbolInformation,
    kindForType,
    locationFromRange,
    workspaceIndexedSymbols,
  )
import SessionText (wordChar)
import SessionTypes
  ( CachedDocument (..),
    Documents (..),
    IndexedSymbol (..),
    MatchMode (..),
    ReferenceTarget (..),
    SemanticToken (..),
    WorkspaceDocument (..),
  )
import SessionWorkspace
  ( findBuiltinsFile,
    findWorkspaceRoot,
    hasWorkspaceMarker,
    ignoredDirectory,
    isSourceFile,
    workspaceFilesFor,
  )
import Subtyping (resolveType)
import Syntax
import System.FilePath (normalise, takeDirectory, (</>))
import Type

-- Document cache, workspace, symbol index, reference, and semantic-token
-- data types live in 'SessionTypes'; this module re-imports them so existing
-- call sites and tests keep importing them from 'Session'.

-- documentsFromList and lookupDocumentText live in 'SessionDocuments'.

-- (Type definitions moved to 'SessionTypes'.)

-- updateDocuments and closeDocuments live in 'SessionDocuments'.

-- | Compute hover information for the requested position.
--
-- Hover prefers the cached document text so editors see immediate results after
-- unsaved edits. When the file is not cached yet, the helper falls back to
-- disk and renders a readable error when loading fails.
hoverDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
hoverDocument readDocument analyze docs msg = do
  let params = field "params" msg
      textDocument = params >>= field "textDocument"
      position = params >>= field "position"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
      lineNo = maybe 0 asInt (position >>= field "line")
      charNo = maybe 0 asInt (position >>= field "character")
  contentResult <- loadDocumentContent readDocument docs file
  case contentResult of
    Left err -> pure (hoverResult (Left err) "" lineNo charNo)
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (hoverResult result content lineNo charNo)

-- | Compute completion items for the requested position.
--
-- Completion analyzes the latest cached text so editor suggestions can follow
-- unsaved changes. The payload is still useful when analysis fails because the
-- helper returns an empty, well-formed completion list instead of crashing the
-- protocol exchange.
completionDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
completionDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left err -> pure (completionResult (Left err) "" lineNo charNo)
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (completionResult result content lineNo charNo)

-- | Resolve a definition/declaration jump for the requested position.
--
-- Top-level names resolve in the current buffer first and then fall back to a
-- workspace-wide symbol index. Dotted selections additionally search field
-- declarations so ambient APIs such as `builtins.map` and local attrset fields
-- behave like editor users expect.
definitionDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
definitionDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure Null
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      workspace <- loadWorkspaceDocuments readDocument analyze docs file
      builtinsFile <- findBuiltinsFile file
      pure $
        maybe
          Null
          (\(targetFile, targetLine, startChar, endChar) -> location targetFile targetLine startChar endChar)
          (resolveDefinitionLocation file content workspace builtinsFile result lineNo charNo)

-- | Compute references for the selected symbol.
--
-- Local names stay scoped to the active buffer, while dotted members search the
-- workspace so shared ambient surfaces and record-field APIs are discoverable.
referencesDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
referencesDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      workspace <- loadWorkspaceDocuments readDocument analyze docs file
      builtinsFile <- findBuiltinsFile file
      pure . toJSON $
        case resolveReferenceTarget file content workspace builtinsFile result lineNo charNo of
          Nothing -> []
          Just target ->
            [ location path foundLine startChar endChar
            | doc <- workspaceDocumentsForTarget workspace target,
              let path = workspaceDocumentFile doc,
              (foundLine, startChar, endChar) <- symbolRanges (workspaceDocumentContent doc) (referenceTargetNeedle target) (referenceTargetMode target)
            ]

-- | Highlight occurrences of the selected symbol inside the active buffer.
--
-- Unlike 'referencesDocument', the response is scoped to the current document
-- so editors can paint quick same-file occurrences without paying for the
-- workspace-wide scan. The symbol resolution itself still goes through the
-- shared reference machinery so dotted selections (e.g. @record.foo@) light
-- up the same matches we would jump or rename to.
documentHighlightsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
documentHighlightsDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      workspace <- loadWorkspaceDocuments readDocument analyze docs file
      builtinsFile <- findBuiltinsFile file
      pure . toJSON $
        case resolveReferenceTarget file content workspace builtinsFile result lineNo charNo of
          Nothing -> []
          Just target ->
            [ documentHighlight foundLine startChar endChar
            | (foundLine, startChar, endChar) <-
                symbolRanges content (referenceTargetNeedle target) (referenceTargetMode target)
            ]

-- | Produce a workspace edit that renames the selected symbol.
--
-- The rename strategy mirrors 'referencesDocument': plain local names stay in
-- one file, while member-style names update dotted usages plus declaration
-- sites across the workspace.
renameDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
renameDocument readDocument analyze docs msg = do
  (file, lineNo, charNo, contentResult) <- requestDocument readDocument docs msg
  case (contentResult, field "params" msg >>= field "newName" >>= asText) of
    (Right content, Just newName)
      | not (Text.null newName) -> do
          result <- loadDocumentAnalysis readDocument analyze docs file
          workspace <- loadWorkspaceDocuments readDocument analyze docs file
          builtinsFile <- findBuiltinsFile file
          pure $
            case resolveReferenceTarget file content workspace builtinsFile result lineNo charNo of
              Nothing -> Null
              Just target ->
                let edits =
                      [ (path, map (\(foundLine, startChar, endChar) -> textEdit foundLine startChar endChar newName) ranges)
                      | doc <- workspaceDocumentsForTarget workspace target,
                        let path = workspaceDocumentFile doc,
                        let ranges = symbolRanges (workspaceDocumentContent doc) (referenceTargetNeedle target) (referenceTargetMode target),
                        not (null ranges)
                      ]
                 in workspaceEdit edits
    _ -> pure Null

-- | List document symbols in a flat, editor-friendly shape.
documentSymbolsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
documentSymbolsDocument readDocument analyze docs msg = do
  (file, _, _, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (toJSON (map indexedSymbolInformation (documentIndexedSymbols file content result)))

-- | Search symbols across the surrounding workspace.
workspaceSymbolsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
workspaceSymbolsDocument readDocument analyze docs msg =
  case workspaceSeedFile docs of
    Nothing -> pure (toJSON ([] :: [Value]))
    Just seedFile -> do
      workspace <- loadWorkspaceDocuments readDocument analyze docs seedFile
      let query = Text.toCaseFold (fromMaybe "" (field "params" msg >>= field "query" >>= asText))
          matches symbol =
            Text.null query
              || query `Text.isInfixOf` Text.toCaseFold (indexedSymbolName symbol)
              || maybe False ((query `Text.isInfixOf`) . Text.toCaseFold) (indexedSymbolContainer symbol)
          symbols = take 200 (filter matches (workspaceIndexedSymbols workspace))
      pure (toJSON (map indexedSymbolInformation symbols))

-- | Offer quick fixes for current diagnostics.
--
-- The server surfaces lightweight escape hatches (`@tnix-ignore`,
-- `@tnix-expected`) and, for obvious misspellings, a rename replacement based
-- on nearby in-scope symbol names.
codeActionsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
codeActionsDocument readDocument analyze docs msg = do
  (file, _, _, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      workspace <- loadWorkspaceDocuments readDocument analyze docs file
      let diagnostics = diagnosticPayloads msg
          candidates = nub (documentCandidateNames result <> map indexedSymbolName (workspaceIndexedSymbols workspace) <> ["builtins", "import"])
          actions =
            concatMap
              ( \diagnostic ->
                  let message = fromMaybe "" (field "message" diagnostic >>= asText)
                      fixes = directiveActions file content diagnostic
                      renameFix =
                        case (diagnosticRange diagnostic, diagnosticSymbolName message, closestCandidate candidates =<< diagnosticSymbolName message) of
                          (Just (lineNo, startChar, endChar), Just current, Just replacement)
                            | current /= replacement ->
                                [ quickFixAction
                                    ("Replace with `" <> replacement <> "`")
                                    file
                                    [textEdit lineNo startChar endChar replacement]
                                ]
                          _ -> []
                   in fixes <> renameFix
              )
              diagnostics
      pure (toJSON actions)

-- | Return LSP folding ranges for one document.
--
-- The provider is text-driven so it keeps emitting folds even when the buffer
-- has type errors or fails to parse cleanly.
foldingRangesDocument ::
  (FilePath -> IO (Either String Text)) ->
  Documents ->
  Value ->
  IO Value
foldingRangesDocument readDocument docs msg = do
  let textDocument = field "params" msg >>= field "textDocument"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
  contentResult <- loadDocumentContent readDocument docs file
  pure $ case contentResult of
    Left _ -> toJSON ([] :: [Value])
    Right content -> toJSON (encodeFoldingRanges (foldingRangesFor content))

-- | Surface every @import@ / @declare@ target inside the document as a
-- clickable LSP DocumentLink.
--
-- The scan is text-driven (see 'SessionLinks.findDocumentLinks') and
-- resolves relative paths against the source file's directory so editors
-- can jump straight to the referenced @.nix@ / @.tnix@ / @.d.tnix@ file.
documentLinksDocument ::
  (FilePath -> IO (Either String Text)) ->
  Documents ->
  Value ->
  IO Value
documentLinksDocument readDocument docs msg = do
  let textDocument = field "params" msg >>= field "textDocument"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
  contentResult <- loadDocumentContent readDocument docs file
  pure $ case contentResult of
    Left _ -> toJSON ([] :: [Value])
    Right content ->
      let baseDir = takeDirectory file
       in toJSON (encodeDocumentLinks baseDir (findDocumentLinks content))

-- | Surface inferred-type inlay hints for unannotated top-level @let@
-- bindings.
--
-- The hint position is the UTF-16 column right after the bound name, and
-- the label is @:: Scheme@ rendered through the shared 'Pretty' helpers
-- so editors render the same text the hover already shows.
inlayHintsDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
inlayHintsDocument readDocument analyze docs msg = do
  let textDocument = field "params" msg >>= field "textDocument"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
  contentResult <- loadDocumentContent readDocument docs file
  case contentResult of
    Left _ -> pure (toJSON ([] :: [Value]))
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (toJSON (encodeInlayHints (inlayHintsFor content result)))

-- | Return LSP semantic tokens for one document.
semanticTokensDocument ::
  (FilePath -> IO (Either String Text)) ->
  (FilePath -> Text -> IO (Either String Analysis)) ->
  Documents ->
  Value ->
  IO Value
semanticTokensDocument readDocument analyze docs msg = do
  (file, _, _, contentResult) <- requestDocument readDocument docs msg
  case contentResult of
    Left _ -> pure (object ["data" .= ([] :: [Int])])
    Right content -> do
      result <- loadDocumentAnalysis readDocument analyze docs file
      pure (object ["data" .= encodeSemanticTokens (semanticTokensFor content result)])

requestDocument ::
  (FilePath -> IO (Either String Text)) ->
  Documents ->
  Value ->
  IO (FilePath, Int, Int, Either String Text)
requestDocument readDocument docs msg = do
  let params = field "params" msg
      textDocument = params >>= field "textDocument"
      position = params >>= field "position"
      file = maybe "" (normalise . uriPath) (textDocument >>= field "uri" >>= asText)
      lineNo = maybe 0 asInt (position >>= field "line")
      charNo = maybe 0 asInt (position >>= field "character")
  contentResult <- loadDocumentContent readDocument docs file
  pure (file, lineNo, charNo, contentResult)

-- loadDocumentContent / loadDocumentAnalysis / loadWorkspaceDocuments live in 'SessionDocuments'.

-- Reference / definition resolution (workspaceDocumentsForTarget,
-- resolveDefinitionLocation, resolveReferenceTarget, symbolRanges,
-- all*Ranges) lives in 'SessionReferences'.

-- Symbol indexing helpers (documentIndexedSymbols, workspaceIndexedSymbols,
-- indexedSymbolInformation, documentCandidateNames, kindForType,
-- findDeclareRange, locationFromRange) live in 'SessionSymbols'.

-- workspaceSeedFile lives in 'SessionDocuments'.

-- Workspace traversal helpers live in 'SessionWorkspace' so they can be
-- unit-tested in isolation. Re-exported here for back-compat with callers
-- that still import them from 'Session'.

-- symbolRanges and all*Ranges live in 'SessionReferences'.

-- Span helpers and character classification live in 'SessionText'.

-- findDeclareRange and kindForType live in 'SessionSymbols'.

-- Edit/diagnostic/quickfix helpers live in 'SessionDiagnostics'.

-- The semantic-tokens provider lives in 'SessionSemanticTokens'.

-- locationFromRange lives in 'SessionSymbols'.

-- lookupCachedDocument / insertDocument / deleteDocument / effectiveCachedAnalysis live in 'SessionDocuments'.
