-- | Alias expansion and type-pattern utilities.
--
-- This module is the workhorse behind generic aliases, higher-kinded encodings,
-- and TypeScript-style `infer` patterns. The rest of the checker treats these
-- capabilities as structural rewrites over 'Type'.
module Alias
  ( AliasEnv,
    collectApps,
    expandAliases,
    flattenUnion,
    matchPattern,
    mkAliasEnv,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Type

-- | Environment keyed by alias name.
type AliasEnv = Map Name TypeAlias

-- | Build an alias environment from parsed declarations.
--
-- Later declarations with the same name win, which mirrors the simple \"last
-- definition in scope\" strategy used elsewhere in this prototype.
mkAliasEnv :: [TypeAlias] -> AliasEnv
mkAliasEnv = Map.fromList . map (\alias -> (typeAliasName alias, alias))

-- | Normalize nested unions and remove duplicates.
--
-- This keeps joins and alias expansion from producing deeply nested `a | (b |
-- c)` shapes that are annoying for both users and subsequent algorithms.
--
-- A repeated member keeps the position of its /last/ occurrence, which is what
-- callers already depend on for stable rendering. Deduplication runs through a
-- 'Set' rather than a linear membership scan, so a wide union costs
-- @O(n log n)@ instead of @O(n^2)@ — joins over unions of a few hundred
-- members were the dominant cost in the checker before that change.
flattenUnion :: Type -> Type
flattenUnion (TUnion members) =
  case reverse (dedupe Set.empty (reverse (concatMap expand members))) of
    [] -> TUnion []
    [single] -> single
    xs -> TUnion xs
  where
    expand (TUnion xs) = concatMap expand xs
    expand other = [other]
    dedupe _ [] = []
    dedupe seen (item : rest)
      | item `Set.member` seen = dedupe seen rest
      | otherwise = item : dedupe (Set.insert item seen) rest
flattenUnion other = other

-- | Split a left-associated type application into its head and arguments.
--
-- `F A B` is represented as `TApp (TApp F A) B`, while many alias algorithms
-- want the pair `(F, [A, B])`.
collectApps :: Type -> (Type, [Type])
collectApps = go []
  where
    go acc (TApp f x) = go (x : acc) f
    go acc headTy = (headTy, acc)

-- | Maximum number of chained alias expansions performed on any one path.
--
-- The budget exists to stop self-referential aliases from diverging. It counts
-- /expansions/, not structural depth, so an ordinary type stays fully expanded
-- no matter how deeply it nests — the previous depth-per-node accounting
-- silently stopped expanding aliases below 32 levels of nesting and therefore
-- made 'expandAliases' non-idempotent on large types.
aliasExpansionBudget :: Int
aliasExpansionBudget = 32

-- | Expand type aliases up to a fixed recursion budget.
--
-- The implementation is intentionally eager enough to make hovers and emitted
-- declarations useful, while still guarding against runaway self-recursive
-- aliases.
expandAliases :: AliasEnv -> Type -> Type
expandAliases env = go 0
  where
    go :: Int -> Type -> Type
    go depth ty
      | depth > aliasExpansionBudget = ty
      | otherwise =
          case ty of
            TCon name
              | Just alias <- Map.lookup name env,
                null (typeAliasParams alias) ->
                  go (depth + 1) (typeAliasBody alias)
            TTypeList items -> TTypeList (map (go depth) items)
            TFun mult a b -> TFun mult (go depth a) (go depth b)
            TRecord fields -> TRecord (fmap (go depth) fields)
            TUnion members -> flattenUnion (TUnion (map (go depth) members))
            TApp f x -> reduce depth (go depth f) (go depth x)
            TForall vars body -> TForall vars (go depth body)
            TConditional a b c d -> TConditional (go depth a) (go depth b) (go depth c) (go depth d)
            other -> other

    reduce :: Int -> Type -> Type -> Type
    reduce depth f x =
      case collectApps (TApp f x) of
        (TCon name, args)
          | Just alias <- Map.lookup name env,
            length args >= length (typeAliasParams alias) ->
              let (used, rest) = splitAt (length (typeAliasParams alias)) args
                  subst = Map.fromList (zip (typeAliasParams alias) used)
                  body = substituteTypeVars subst (typeAliasBody alias)
               in foldl TApp (go (depth + 1) body) rest
        (headTy, args) -> foldl TApp headTy args

-- | Match a concrete type against a pattern containing 'TInfer' placeholders.
--
-- This is the structural heart of conditional types: when a pattern matches, we
-- recover the inferred bindings and substitute them into the `true` branch.
matchPattern :: Type -> Type -> Maybe (Map Name Type)
matchPattern = go Map.empty
  where
    go env value (TInfer name) =
      case Map.lookup name env of
        Nothing -> Just (Map.insert name value env)
        Just prev | prev == value -> Just env
        _ -> Nothing
    go env (TFun actualMult a b) (TFun patternMult c d)
      | actualMult == patternMult = go env a c >>= \env' -> go env' b d
      | otherwise = Nothing
    go env (TRecord a) (TRecord b) = foldl step (Just env) (Map.toList b)
      where
        step acc (name, ty) = do
          env' <- acc
          actualTy <- Map.lookup name a
          go env' actualTy ty
    go env (TTypeList actualItems) (TTypeList patternItems)
      | length actualItems == length patternItems =
          foldl
            (\acc (actualTy, nextPatternTy) -> acc >>= \env' -> go env' actualTy nextPatternTy)
            (Just env)
            (zip actualItems patternItems)
      | otherwise = Nothing
    go env (TApp a b) (TApp c d) = go env a c >>= \env' -> go env' b d
    go env value other | value == other = Just env
    go _ _ _ = Nothing
