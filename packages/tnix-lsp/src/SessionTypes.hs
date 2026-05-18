{-# LANGUAGE OverloadedStrings #-}

-- | Shared data types used across the LSP session.
--
-- This module is intentionally light on logic: it holds the records and
-- enums that flow between the document cache, workspace traversal, symbol
-- index, and per-request handlers. Keeping the types in one place breaks
-- circular imports as the rest of `Session.hs` continues to be split into
-- focused modules.
module SessionTypes
  ( -- * Document cache
    CachedDocument (..),
    Documents (..),

    -- * Workspace-wide views
    WorkspaceDocument (..),

    -- * Symbol index
    IndexedSymbol (..),

    -- * Reference resolution
    MatchMode (..),
    ReferenceTarget (..),

    -- * Semantic tokens
    SemanticToken (..),
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Driver (Analysis)

-- | A single cached buffer plus the latest analysis result.
--
-- @cachedDocumentLastGoodAnalysis@ is preserved across temporary parser /
-- type errors so editor features like hover keep returning useful answers
-- while the user is mid-edit.
data CachedDocument = CachedDocument
  { cachedDocumentText :: Text
  , cachedDocumentAnalysis :: Maybe (Either String Analysis)
  , cachedDocumentLastGoodAnalysis :: Maybe Analysis
  }
  deriving (Eq, Show)

-- | In-memory document cache keyed by normalized file path.
newtype Documents = Documents {unDocuments :: Map FilePath CachedDocument}
  deriving (Eq, Show)

instance Semigroup Documents where
  Documents left <> Documents right = Documents (left <> right)

instance Monoid Documents where
  mempty = Documents Map.empty

-- | One workspace file loaded for cross-file analysis.
--
-- Carries the analysis result alongside the source text so per-file
-- handlers can answer questions about a buffer they have never actively
-- opened.
data WorkspaceDocument = WorkspaceDocument
  { workspaceDocumentFile :: FilePath
  , workspaceDocumentContent :: Text
  , workspaceDocumentAnalysis :: Either String Analysis
  }

-- | Symbol surfaced through documentSymbol / workspaceSymbol.
--
-- The 'indexedSymbolRange' triple is @(line, startChar, endChar)@ already
-- expressed in UTF-16 columns so callers can pass it through to LSP
-- directly.
data IndexedSymbol = IndexedSymbol
  { indexedSymbolName :: Text
  , indexedSymbolKind :: Int
  , indexedSymbolFile :: FilePath
  , indexedSymbolRange :: (Int, Int, Int)
  , indexedSymbolContainer :: Maybe Text
  }

-- | How a reference search should match a symbol against source text.
--
-- @WholeWordMatch@ is used for ordinary bindings; @FieldWordMatch@ adds
-- the dot-prefixed field form so `record.foo` references are picked up
-- when searching for @foo@.
data MatchMode
  = WholeWordMatch
  | FieldWordMatch

-- | A resolved target for a references / rename request.
data ReferenceTarget = ReferenceTarget
  { referenceTargetFiles :: [FilePath]
  , referenceTargetNeedle :: Text
  , referenceTargetMode :: MatchMode
  }

-- | One delta entry emitted by the semantic-tokens provider.
data SemanticToken = SemanticToken
  { semanticTokenLine :: Int
  , semanticTokenStart :: Int
  , semanticTokenLength :: Int
  , semanticTokenType :: Int
  }
