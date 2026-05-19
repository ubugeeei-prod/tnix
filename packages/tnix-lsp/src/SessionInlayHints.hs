{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Inlay-hint provider for the tnix LSP.
--
-- Emits @:: Scheme@ hints next to top-level @let@ bindings that the
-- programmer has not annotated themselves. Gradual typing is most
-- valuable when the inferred shape is visible at a glance, and inlay
-- hints are how editors surface that information without forcing the
-- author to write the annotation by hand.
--
-- 'inlayHintsFor' is pure so the spec suite can exercise the formatting
-- and skip rules without touching the LSP plumbing.
module SessionInlayHints
  ( InlayHint (..),
    encodeInlayHints,
    inlayHintsFor,
  )
where

import Data.Aeson (Value, object, (.=))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Driver (Analysis (..))
import Pretty (renderScheme)
import Server (findDefinitionRange)
import Syntax (Expr (..), LetItem (..), Marked (..), Program (..))
import Type (Name, Scheme)

-- | Internal inlay-hint value. Coordinates are line and UTF-16 column.
data InlayHint = InlayHint
  { inlayHintLine :: !Int
  , inlayHintCharacter :: !Int
  , inlayHintLabel :: !Text
  }
  deriving (Eq, Show)

-- | Encode one or more inlay hints into the LSP wire array.
--
-- We always emit kind @1@ (Type) and request a leading pad so the
-- @:: T@ payload sits one space to the right of the identifier.
encodeInlayHints :: [InlayHint] -> [Value]
encodeInlayHints = map encode1
 where
  encode1 (InlayHint line ch label) =
    object
      [ "position" .= object ["line" .= line, "character" .= ch]
      , "label" .= label
      , "kind" .= (1 :: Int)
      , "paddingLeft" .= True
      ]

-- | Compute inlay hints for one document.
--
-- Returns hints only when the analyzer produced a result. We deliberately
-- restrict ourselves to top-level @let@ bindings whose name does not
-- already have a sibling @LetSignature@ — the assumption is that the
-- programmer adds an explicit annotation when they want the type to be
-- the authority, and we should not double up.
inlayHintsFor :: Text -> Either String Analysis -> [InlayHint]
inlayHintsFor content (Right analysis) =
  let items = topLevelLetItems (analysisProgram analysis)
   in collectHints content (analysisBindings analysis) items
inlayHintsFor _ _ = []

topLevelLetItems :: Program -> [LetItem]
topLevelLetItems prog = case programExpr prog of
  Just (Marked _ (ELet items _)) -> map markedValue items
  _ -> []

collectHints :: Text -> Map.Map Name Scheme -> [LetItem] -> [InlayHint]
collectHints content bindings items =
  [ InlayHint line endChar (":: " <> renderScheme scheme)
  | item <- items
  , Just name <- [bindingName item]
  , not (hasSignature name items)
  , Just scheme <- [Map.lookup name bindings]
  , Just (line, _, endChar) <- [findDefinitionRange content name]
  ]

bindingName :: LetItem -> Maybe Name
bindingName = \case
  LetBinding name _ -> Just name
  _ -> Nothing

hasSignature :: Name -> [LetItem] -> Bool
hasSignature name = any sameSignature
 where
  sameSignature (LetSignature n _) = n == name
  sameSignature _ = False
