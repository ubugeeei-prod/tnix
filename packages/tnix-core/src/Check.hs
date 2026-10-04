{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Gradual type checker and local inference engine for tnix.
--
-- The checker intentionally aims for useful incremental feedback rather than
-- whole-program soundness. `dynamic` is built in, imports can be typed from
-- ambient declarations, and remaining inference variables are surfaced as
-- polymorphic schemes instead of forcing runtime evidence.
module Check
  ( CheckContext (..),
    CheckError (..),
    CheckResult (..),
    checkProgram,
    checkProgramDetailed,
    collapseParentSegments,
    resolvePath,
  )
where

import Alias
import Control.Applicative ((<|>))
import Control.Monad (foldM, forM, forM_, unless, void, when, zipWithM)
import Control.Monad.State.Strict
import Data.Functor (($>), (<&>))
import Data.List (group, intercalate, isInfixOf, nub, sort)
import Data.Graph (flattenSCC, stronglyConnComp)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set qualified as Set
import Data.Text qualified as T
import Diagnostics (DiagnosticCode (..), withCode)
import Indexed
import Pretty (renderType)
import Subtyping
import Syntax
import System.FilePath (isAbsolute, joinPath, normalise, splitDirectories, takeDirectory, (</>))
import Type

-- | Inputs required to analyze one file.
--
-- `checkAmbient` represents the ambient world visible from the current file,
-- while `checkAliases` contains both local aliases and any imported declaration
-- aliases that were discovered by the driver.
data CheckContext = CheckContext
  { checkAliases :: AliasEnv,
    checkAmbient :: Map FilePath Scheme,
    checkFile :: FilePath,
    -- | True inside the body of a `with` whose scope type is not a known
    -- record, so unresolved names degrade to `dynamic` instead of erroring.
    checkOpenScope :: Bool
  }

-- | User-visible results produced by checking a program.
--
-- The root scheme describes the file's resulting expression, while
-- `resultBindings` records the final types of `let`-bound names for CLI output
-- and LSP hover.
data CheckResult = CheckResult
  { resultRoot :: Maybe Scheme,
    resultBindings :: Map Name Scheme
  }
  deriving (Eq, Show)

-- | A checker failure: the coded message plus, when known, the innermost
-- source region whose inference raised it.
data CheckError = CheckError
  { checkErrorMessage :: String,
    checkErrorSpan :: Maybe SrcSpan
  }
  deriving (Eq, Show)

-- | Inference state: the meta supply, solved metas, and the set of "soft"
-- metas. A soft meta stands for an injected dependency whose real type is
-- unknown and usually polymorphic (an attrset-pattern argument such as
-- `fetchFromGitHub`, or a field selected from an unknown record such as
-- `lib.mkOption`). Calling one is gradual rather than pinning it to the
-- monotype of the first call site.
data InferState = InferState {nextMeta :: Int, substitutions :: Map Int Type, softMetas :: Set.Set Int}

type InferM = StateT InferState (Either CheckError)

type TypeEnv = Map Name Scheme

-- | Abort inference with a (coded) message. The span is attached by the
-- nearest enclosing 'ELoc' as the error propagates outward.
throwCheck :: String -> InferM a
throwCheck message = lift (Left (CheckError message Nothing))

-- | Run an inference step, attributing any span-less failure to @region@.
withSpan :: SrcSpan -> InferM a -> InferM a
withSpan region action =
  StateT $ \st ->
    case runStateT action st of
      Left err@CheckError{checkErrorSpan = Nothing} -> Left err{checkErrorSpan = Just region}
      other -> other

-- | Attribute failures of @action@ to @expr@'s source span, if it has one.
atSpanOf :: Expr -> InferM a -> InferM a
atSpanOf = \case
  ELoc region _ -> withSpan region
  _ -> id

-- | Strip the outermost location wrappers to inspect an expression's shape.
unloc :: Expr -> Expr
unloc = \case
  ELoc _ inner -> unloc inner
  other -> other

-- | Check a parsed program and infer its public types.
--
-- The built-in environment is intentionally tiny: `builtins` is left fully
-- dynamic and `import` only promises that a path yields something. Ambient
-- declarations refine imports when they are available.
--
-- The checker follows a "best effort but explicit" policy:
--
-- * annotations are respected when they are structurally satisfied,
-- * gradual behavior only kicks in when `dynamic` is genuinely involved,
-- * unresolved inference variables are closed into stable schemes before
--   results escape the module.
--
-- Representative examples:
--
-- @
-- let id = x: x; in id
--   => forall a. a -> a
--
-- let xs :: Vec (Range 2 4 Nat) Int; xs = [1 2 3]; in xs
--   => accepted
--
-- let xs :: Vec (2 | Range 4 8 Nat) Int; xs = [1 2 3]; in xs
--   => rejected
-- @
checkProgram :: CheckContext -> Program -> Either String CheckResult
checkProgram ctx = either (Left . checkErrorMessage) Right . checkProgramDetailed ctx

-- | Like 'checkProgram', but keeps the source span of the failure.
checkProgramDetailed :: CheckContext -> Program -> Either CheckError CheckResult
checkProgramDetailed ctx program =
  evalStateT (inferTop ctx (globalEnvironment ctx)) (InferState 0 Map.empty Set.empty)
  where

    inferTop local env = case programExpr program of
      Nothing -> pure (CheckResult Nothing Map.empty)
      Just markedExpr -> inferRootExpression local env markedExpr

-- | The names Nix puts in scope without a `builtins.` prefix.
--
-- Each global shares its type with the matching `builtins` member when the
-- ambient `builtins` declaration provides one, so richer declarations flow to
-- both spellings automatically. Missing members fall back to a conservative
-- built-in signature or `dynamic`.
globalEnvironment :: CheckContext -> TypeEnv
globalEnvironment ctx =
  Map.fromList $
    [ ("builtins", builtinsScheme),
      ("import", Scheme [] (TFun Many tPath tDynamic))
    ]
      <> [(name, memberScheme name) | name <- globalBuiltinNames]
  where
    builtinsScheme = Map.findWithDefault (Scheme [] tDynamic) "builtins" (checkAmbient ctx)
    memberScheme name =
      case lookupRecordField (checkAliases ctx) (schemeType builtinsScheme) name of
        Just fieldTy -> schemeFromAnnotation fieldTy
        Nothing -> fallbackGlobal name
    fallbackGlobal = \case
      "throw" -> Scheme ["a"] (TFun Many tString (TVar "a"))
      "abort" -> Scheme ["a"] (TFun Many tString (TVar "a"))
      "toString" -> Scheme [] (TFun Many tDynamic tString)
      "isNull" -> Scheme [] (TFun Many tDynamic tBool)
      "baseNameOf" -> Scheme [] (TFun Many tDynamic tString)
      "map" -> Scheme ["a", "b"] (TFun Many (TFun Many (TVar "a") (TVar "b")) (TFun Many (tList (TVar "a")) (tList (TVar "b"))))
      _ -> Scheme [] tDynamic

-- | Builtins that Nix also exposes as top-level identifiers.
globalBuiltinNames :: [Name]
globalBuiltinNames =
  [ "abort",
    "baseNameOf",
    "break",
    "derivation",
    "derivationStrict",
    "dirOf",
    "fetchGit",
    "fetchMercurial",
    "fetchTarball",
    "fetchTree",
    "fromTOML",
    "isNull",
    "map",
    "placeholder",
    "removeAttrs",
    "scopedImport",
    "throw",
    "toString"
  ]

-- | Infer the type of one expression under the current local environment.
--
-- The function is syntax-directed except for applications and annotations,
-- where it consults `constrain`/`unify` to reconcile inferred and expected
-- structure. List literals delegate to `inferListType`, which means exact
-- vector, matrix, or tensor shapes can be recovered directly from surface list
-- syntax.
--
-- Representative examples:
--
-- @
-- inferExpr [] [1 2]
--   => Vec 2 (1 | 2)
--
-- inferExpr [] [[1 2] [3 4]]
--   => Matrix 2 2 (1 | 2 | 3 | 4)
--
-- inferExpr [] (import ./unknown.nix)
--   => dynamic
--
-- inferExpr [] ({ value = 1; } as { value :: Int; })
--   => { value :: Int; }
-- @
inferExpr :: CheckContext -> TypeEnv -> Expr -> InferM Type
inferExpr ctx env = \case
  ELoc region inner -> withSpan region (inferExpr ctx env inner)
  EVar name ->
    case Map.lookup name env of
      Just scheme -> instantiate scheme
      Nothing
        | checkOpenScope ctx -> pure tDynamic
        | otherwise -> throwCheck (withCode TC0001UnboundName ("unbound name: " <> quoteName name))
  EString text -> pure (TLit (LString (stringLiteralText text)))
  EInterp _ parts -> do
    mapM_ (\case StrExpr expr -> void (inferExpr ctx env expr); _ -> pure ()) parts
    pure tString
  EFloat n -> pure (TLit (LFloat n))
  EInt n -> pure (TLit (LInt n))
  EBool b -> pure (TLit (LBool b))
  ENull -> pure tNull
  EPath _ -> pure tPath
  ESearchPath _ -> pure tPath
  EPathInterp parts -> do
    mapM_ (\case StrExpr expr -> void (inferExpr ctx env expr); _ -> pure ()) parts
    pure tPath
  ELambda pattern' body -> do
    (argTy, patternEnv) <- inferPatternBindings ctx env pattern'
    bodyTy <- inferExpr ctx (patternEnv <> env) body
    pure (TFun (inferLambdaMultiplicity pattern' body) argTy bodyTy)
  EApp fun arg
    | EVar "import" <- unloc fun,
      Just target <- importTarget (unloc arg),
      -- Only the builtin `import` resolves ambient declarations; a local
      -- binding named `import` shadows it, as in Nix.
      Map.lookup "import" env == Map.lookup "import" (globalEnvironment ctx) ->
        maybe (pure tDynamic) instantiate (Map.lookup (resolvePath (checkFile ctx) target) (checkAmbient ctx))
  EApp fun arg -> do
    funTy <- inferExpr ctx env fun >>= zonk
    argTy <- inferExpr ctx env arg
    let resolvedFunTy = resolveType (checkAliases ctx) funTy
    if resolvedFunTy == tDynamic
      then pure tDynamic
      else
        if resolvedFunTy == tAny
          then pure tAny
          else case resolvedFunTy of
            TFun _ domTy outTy -> atSpanOf arg (constrain ctx argTy domTy) *> zonk outTy
            _
              | definitelyNotCallable resolvedFunTy ->
                  throwCheck (withCode TC0018NotCallable ("cannot call " <> describeNonCallable resolvedFunTy <> " as a function"))
              | TMeta n <- resolvedFunTy -> do
                  soft <- isSoftMeta n
                  if soft
                    then do
                      -- An injected dependency: stay gradual instead of
                      -- fixing its type from this one call site.
                      _ <- bindMeta n (TFun Many tDynamic tDynamic)
                      pure tDynamic
                    else applyUnknown ctx funTy argTy
              | otherwise -> applyUnknown ctx funTy argTy
  EBinaryOp op left right -> inferBinaryOp ctx env op left right
  EUnaryOp OpNot operand -> do
    operandTy <- inferExpr ctx env operand
    _ <- constrain ctx operandTy tBool
    pure tBool
  EUnaryOp OpNeg operand -> do
    operandTy <- inferExpr ctx env operand >>= zonk
    let resolved = resolveType (checkAliases ctx) operandTy
    if resolved == tAny || resolved == tDynamic
      then pure resolved
      else do
        _ <- constrain ctx operandTy tNumber
        pure (maybe tNumber widenSingleNumericFamily (numericFamily resolved))
  EHasAttr base steps -> do
    _ <- inferExpr ctx env base
    forM_ [key | SelectDynamic key <- steps] $ \key -> do
      keyTy <- inferExpr ctx env key
      constrain ctx keyTy tString
    pure tBool
  EAssert cond body -> do
    condTy <- inferExpr ctx env cond
    _ <- constrain ctx condTy tBool
    inferExpr ctx env body
  EWith scope body -> do
    scopeTy <- inferExpr ctx env scope >>= zonk
    case resolveType (checkAliases ctx) scopeTy of
      -- A known record contributes its fields (lexical bindings still win), and
      -- truly-unbound names in the body remain errors.
      TRecord fields -> inferExpr ctx (Map.union env (Map.map (Scheme []) fields)) body
      -- Any other scope (dynamic, unknown, ...) cannot be enumerated, so the
      -- body is checked with an open scope where unresolved names are dynamic.
      _ -> inferExpr ctx{checkOpenScope = True} env body
  ELet items body -> do
    (env', _) <- inferLet ctx env items
    inferExpr ctx env' body
  EAttrSet rawItems -> do
    (items, dynamicEntries) <- normalizeAttrItems rawItems
    fields <- concat <$> traverse inferAttr items
    case duplicateNames (map fst fields) of
      dup : _ -> throwCheck (withCode TC0002DuplicateAttribute ("duplicate attribute: " <> quoteName dup))
      [] -> finishAttrSet ctx env dynamicEntries (Map.fromList fields)
    where
      inferAttr = \case
        AttrField name expr -> do
          ty <- inferExpr ctx env expr
          pure [(name, ty)]
        AttrInherit names ->
          traverse (\name -> inferExpr ctx env (EVar name) >>= \ty -> pure (name, ty)) names
        AttrInheritFrom source names -> inferInheritFrom ctx env source names
        AttrPath _ _ -> pure []
  ERec items -> inferRecAttrSet ctx env items
  ESelectOr base fields fallback -> do
    fallbackTy <- inferExpr ctx env fallback
    baseTy <- inferExpr ctx env base >>= zonk
    -- `x.a or d` must not *require* `a`: when the path runs into a value whose
    -- shape is still unknown, the result is just the fallback's type joined
    -- with a fresh unknown, and no row requirement is recorded.
    known <- pathIsKnown ctx env baseTy fields
    attempt <-
      if known
        then catchInfer (inferExpr ctx env (ESelect base fields))
        else Right <$> freshMeta
    case attempt of
      Right selectedTy -> do
        selected <- zonk selectedTy
        fallback' <- zonk fallbackTy
        pure (joinTypes (checkAliases ctx) selected fallback')
      Left err
        | isMissingFieldError err -> do
            -- The base must still type-check on its own; only the missing
            -- path is covered by the default.
            _ <- inferExpr ctx env base
            pure fallbackTy
        | otherwise -> lift (Left err)
  ESelect base fields -> do
    baseTy <- inferExpr ctx env base
    foldM step baseTy fields
    where
      step ty field =
        case field of
          SelectName name -> inferStaticSelect ctx ty name
          SelectDynamic expr -> do
            keyTy <- inferExpr ctx env expr
            inferDynamicSelect ctx ty keyTy
  EIf cond yesExpr noExpr -> do
    condTy <- inferExpr ctx env cond
    _ <- constrain ctx condTy tBool
    yesTy <- inferExpr ctx env yesExpr >>= zonk
    noTy <- inferExpr ctx env noExpr >>= zonk
    joinBranches ctx yesTy noTy
  EList members ->
    traverse (inferExpr ctx env) members
      <&> inferListType (joinTypes (checkAliases ctx))
  ECast expr assertedTy -> do
    actualTy <- inferExpr ctx env expr
    checkCast ctx actualTy assertedTy

-- | Whether every step of a selection path can be resolved without guessing:
-- the base (and each intermediate value) has a known shape.
pathIsKnown :: CheckContext -> TypeEnv -> Type -> [SelectStep] -> InferM Bool
pathIsKnown _ _ _ [] = pure True
pathIsKnown ctx env ty (step : rest) = do
  ty' <- zonk ty
  case resolveType (checkAliases ctx) ty' of
    TMeta _ -> pure False
    TOpenRecord fields (TMeta _)
      | SelectName name <- step,
        not (Map.member name fields) ->
          pure False
    resolved
      | SelectName name <- step,
        Just fieldTy <- lookupRecordField (checkAliases ctx) resolved name ->
          pathIsKnown ctx env fieldTy rest
      | otherwise -> pure True

-- | Join the two branches of a conditional. While metas are involved the
-- branches are unified (after widening literals, so `true`/`false` meet at
-- `Bool`), which is what lets recursive definitions such as mutually
-- recursive `even`/`odd` solve; fully known branches keep their precise join.
joinBranches :: CheckContext -> Type -> Type -> InferM Type
joinBranches ctx yesTy noTy
  | hasUnresolvedMetas yesTy noTy = do
      attempt <- catchInfer (unify ctx (widenLiterals yesTy) (widenLiterals noTy))
      case attempt of
        Right ty -> zonk ty
        Left _ -> pure (joinTypes (checkAliases ctx) yesTy noTy)
  | otherwise = pure (joinTypes (checkAliases ctx) yesTy noTy)

-- | Replace singleton literal types by their primitive base.
widenLiterals :: Type -> Type
widenLiterals = \case
  TLit (LInt _) -> tInt
  TLit (LFloat _) -> tFloat
  TLit (LString _) -> tString
  TLit (LBool _) -> tBool
  TRecord fields -> TRecord (fmap widenLiterals fields)
  TOpenRecord fields tail' -> TOpenRecord (fmap widenLiterals fields) tail'
  TOptional inner -> TOptional (widenLiterals inner)
  TFun mult a b -> TFun mult (widenLiterals a) (widenLiterals b)
  TApp f x -> TApp f (widenLiterals x)
  TUnion members -> case nubOrdTypes (map widenLiterals members) of
    [single] -> single
    many' -> TUnion many'
  other -> other
  where
    nubOrdTypes = Set.toList . Set.fromList

isNullLiteral :: Expr -> Bool
isNullLiteral expr =
  case unloc expr of
    ENull -> True
    _ -> False

-- | Apply a callee whose type is not known yet. Its parameter type is
-- inferred from this argument, widened so one call site's literal does not
-- pin the parameter to a singleton.
applyUnknown :: CheckContext -> Type -> Type -> InferM Type
applyUnknown ctx funTy argTy = do
  outTy <- freshMeta
  argTy' <- widenLiterals <$> zonk argTy
  _ <- unify ctx funTy (TFun Many argTy' outTy)
  zonk outTy

-- | Recognize `import <path>` targets that can be resolved statically.
importTarget :: Expr -> Maybe FilePath
importTarget = \case
  EPath raw -> Just raw
  EString raw -> Just (T.unpack (stringLiteralText raw))
  _ -> Nothing

isMissingFieldError :: CheckError -> Bool
isMissingFieldError err =
  any (`isInfixOf` checkErrorMessage err) ["TC0009", "TC0010"]

-- | Infer `inherit (source) a b;` as selections from @source@.
inferInheritFrom :: CheckContext -> TypeEnv -> Expr -> [Name] -> InferM [(Name, Type)]
inferInheritFrom ctx env source names = do
  sourceTy <- inferExpr ctx env source
  traverse (\name -> (,) name <$> inferStaticSelect ctx sourceTy name) names

-- | Fold nested attribute paths into ordinary fields.
--
-- `a.b = 1; a.c = 2;` becomes `a = { b = 1; c = 2; };`, merging with a literal
-- attribute set written for the same key, exactly as Nix does. Entries whose
-- first key is dynamic (`${k} = v;`) cannot be folded statically and are
-- returned separately as key/value expression pairs.
normalizeAttrItems :: [AttrItem] -> InferM ([AttrItem], [(Expr, Expr)])
normalizeAttrItems items = do
  let entries = concatMap entry items
      staticKeys = nub [name | Left (name, _, _) <- entries]
      dynamicEntries = [(key, value) | Right (key, value) <- entries]
      inherits = filter isInherit items
  merged <- traverse (\name -> mergeKey name [(path, value) | Left (key, path, value) <- entries, key == name]) staticKeys
  pure (inherits <> merged, dynamicEntries)
  where
    entry = \case
      AttrField name value -> [Left (name, [], value)]
      AttrPath (SelectName name : rest) value -> [Left (name, rest, value)]
      AttrPath (SelectDynamic key : rest) value -> [Right (key, nestValue rest value)]
      _ -> []
    isInherit = \case
      AttrInherit _ -> True
      AttrInheritFrom _ _ -> True
      _ -> False
    mergeKey name = \case
      [([], value)] -> pure (AttrField name value)
      group' -> AttrField name . EAttrSet . concat <$> traverse (subItems name) group'
    subItems name = \case
      ([], value) ->
        case unloc value of
          EAttrSet nested -> pure nested
          _ -> throwCheck (withCode TC0002DuplicateAttribute ("duplicate attribute: " <> quoteName name))
      (path, value) -> pure [pathItem path value]
    nestValue [] value = value
    nestValue path value = EAttrSet [pathItem path value]
    pathItem [SelectName name] value = AttrField name value
    pathItem path value = AttrPath path value

-- | Close an attribute set's type, accounting for dynamically-named entries.
--
-- Keys must be string-like. An attribute set built only from computed keys is
-- a dictionary (`AttrsOf v`); one mixing static and computed keys keeps its
-- static fields and gets a `dynamic` row for the rest.
finishAttrSet :: CheckContext -> TypeEnv -> [(Expr, Expr)] -> Map Name Type -> InferM Type
finishAttrSet ctx env dynamicEntries fields
  | null dynamicEntries = pure (TRecord fields)
  | otherwise = do
      valueTys <- forM dynamicEntries $ \(key, value) -> do
        keyTy <- inferExpr ctx env key
        _ <- constrain ctx keyTy tString
        inferExpr ctx env value >>= zonk
      let aliases = checkAliases ctx
      pure $
        if Map.null fields
          then -- Only computed keys: a dictionary of the joined value type.
            case valueTys of
              x : xs -> tAttrsOf (foldRight1 (joinTypes aliases) x xs)
              [] -> tAttrsOf tDynamic
          else -- Known fields plus computed keys: keep what is known, open the rest.
            TOpenRecord fields tDynamic

-- | Infer a mutually recursive `let` group.
--
-- The algorithm proceeds in three phases:
--
-- * collect user signatures,
-- * allocate placeholders so recursive bindings may refer to one another,
-- * infer each body and constrain it against its placeholder/signature.
--
-- This arrangement keeps explicit signatures authoritative while still allowing
-- recursive inference for unannotated bindings.
--
-- Representative examples:
--
-- @
-- let
--   id :: forall a. a -> a;
--   id = x: x;
-- in id
--   => keeps the declared polymorphic scheme for `id`
--
-- let
--   value = value;
-- in value
--   => allocates a placeholder first, then constrains recursively
-- @
inferLet :: CheckContext -> TypeEnv -> [Marked LetItem] -> InferM (TypeEnv, Map Name Scheme)
inferLet ctx env items = do
  let sigs = Map.fromList [(name, schemeFromAnnotation ty) | Marked _ (LetSignature name ty) <- items]
      itemDirectives =
        Map.fromListWith
          (\_ earlier -> earlier)
          [(name, directive) | Marked (Just directive) item <- items, name <- letItemNames item]
      plainInherits = concat [names | Marked _ (LetInherit Nothing names) <- items]
      attrItems = concatMap (letItemAttrs . markedValue) items
  let simpleNames = [name | Marked _ (LetBinding name _) <- items] <> concat [names | Marked _ (LetInherit _ names) <- items]
  unless (null (duplicateNames simpleNames)) (throwCheck (withCode TC0004DuplicateBinding ("duplicate bindings: " <> quoteNames (duplicateNames simpleNames))))
  (normalized, dynamicEntries) <- normalizeAttrItems attrItems
  unless (null dynamicEntries) (throwCheck (withCode TC0022DynamicLetBinding "dynamic attributes are not allowed in let"))
  let binds =
        [(name, expr, Map.lookup name itemDirectives) | AttrField name expr <- normalized]
          <> [(name, ESelect source [SelectName name], Map.lookup name itemDirectives) | AttrInheritFrom source names <- normalized, name <- names]
      bindNames = [name | (name, _, _) <- binds]
      allNames = bindNames <> plainInherits
      missing = filter (`notElem` allNames) (Map.keys sigs)
      duplicateSigs = duplicateNames [name | Marked _ (LetSignature name _) <- items]
      duplicateBinds = duplicateNames (bindNames <> plainInherits)
      inheritedScheme name =
        case Map.lookup name env of
          Just scheme -> pure (name, scheme)
          Nothing
            | checkOpenScope ctx -> pure (name, Scheme [] tDynamic)
            | otherwise -> throwCheck (withCode TC0001UnboundName ("unbound name: " <> quoteName name))
  unless (null duplicateSigs) (throwCheck (withCode TC0003DuplicateSignature ("duplicate signatures: " <> quoteNames duplicateSigs)))
  unless (null duplicateBinds) (throwCheck (withCode TC0004DuplicateBinding ("duplicate bindings: " <> quoteNames duplicateBinds)))
  unless (null missing) (throwCheck (withCode TC0005MissingBindingForSignature ("missing bindings for signatures: " <> quoteNames missing)))
  inherited <- Map.fromList <$> traverse inheritedScheme plainInherits
  -- Signed bindings are known up front (enabling polymorphic recursion);
  -- unsigned ones are inferred one dependency group at a time, in
  -- topological order, and generalized as soon as their group is solved.
  -- That is what gives `let` Hindley-Milner polymorphism: a helper used at
  -- two different types later in the same `let` is instantiated freshly.
  let signedEnv = Map.restrictKeys sigs (Set.fromList bindNames)
      baseEnv = signedEnv <> inherited <> env
      bindMap = Map.fromList [(name, (expr, directive)) | (name, expr, directive) <- binds]
      unsigned = Set.fromList [name | name <- bindNames, not (Map.member name sigs)]
      groups =
        stronglyConnComp
          [ (name, name, Set.toList (Set.intersection (exprFreeNames expr) (Set.fromList bindNames)))
            | (name, expr, _) <- binds
          ]
  (finalEnv, inferredList) <- foldM (inferGroup unsigned bindMap) (baseEnv, []) (map flattenSCC groups)
  let finals = Map.fromList inferredList <> inherited
  pure (finals <> finalEnv, finals)
  where
    inferGroup unsigned bindMap (currentEnv, acc) members = do
      placeholders <-
        Map.fromList
          <$> traverse (\name -> (,) name . Scheme [] <$> freshMeta) (filter (`Set.member` unsigned) members)
      let groupEnv = placeholders <> currentEnv
      results <- forM members $ \name -> do
        (expr, inlineDirective) <-
          maybe (throwCheck (withCode TC0017MissingPlaceholder ("internal: missing binding " <> show name))) pure (Map.lookup name bindMap)
        -- A signed binding is checked against its signature with the
        -- quantified variables held *rigid* (skolemized): `forall a. a -> a`
        -- must work for every `a`, so a body returning `1` is rejected.
        -- Other bindings still use the signature polymorphically.
        expected <- case (Map.lookup name (signaturesOf items), Map.lookup name groupEnv) of
          (Just (Scheme _ signatureTy), _) -> pure signatureTy
          (Nothing, Just scheme) -> instantiate scheme
          (Nothing, Nothing) -> throwCheck (withCode TC0017MissingPlaceholder ("internal: missing placeholder for binding " <> show name))
        let directive = inlineDirective <|> Map.lookup name (sigDirectivesOf items)
        attempt <-
          catchInfer $ do
            actual <- inferExpr ctx groupEnv expr
            _ <- atSpanOf expr (constrain ctx actual expected)
            zonk expected
        resolved <-
          case (directive, attempt) of
            (Nothing, Right ty) -> pure ty
            (Nothing, Left err) -> lift (Left err)
            (Just TnixIgnore, Right ty) -> pure ty
            (Just TnixIgnore, Left _) -> recoverSuppressedType ctx expected
            (Just TnixExpected, Left _) -> recoverSuppressedType ctx expected
            (Just TnixExpected, Right _) ->
              throwCheck (withCode TC0006UnusedExpectedDirective ("unused @tnix-expected directive on binding " <> quoteName name))
        pure (name, resolved)
      -- Generalize against the environment *outside* this group, so metas
      -- still shared with enclosing lambdas stay monomorphic.
      generalized <- forM results $ \(name, ty) ->
        case Map.lookup name (signaturesOf items) of
          Just scheme -> pure (name, scheme)
          Nothing -> (,) name <$> generalize currentEnv ty
      pure (Map.fromList generalized <> currentEnv, acc <> generalized)
    sigDirectivesOf xs = Map.fromList [(name, directive) | Marked (Just directive) (LetSignature name _) <- xs]
    signaturesOf xs = Map.fromList [(name, schemeFromAnnotation ty) | Marked _ (LetSignature name ty) <- xs]
    letItemAttrs = \case
      LetBinding name expr -> [AttrField name expr]
      LetPath steps expr -> [AttrPath steps expr]
      LetInherit (Just source) names -> [AttrInheritFrom source names]
      _ -> []
    letItemNames = \case
      LetBinding name _ -> [name]
      LetPath (SelectName name : _) _ -> [name]
      LetInherit _ names -> names
      _ -> []

-- | Infer a recursive attribute set (`rec { ... }`).
--
-- Field bindings may refer to one another, so each declared field name gets a
-- placeholder in scope before any field body is inferred — mirroring `let`.
-- `inherit` clauses resolve against the enclosing scope, not the rec scope.
inferRecAttrSet :: CheckContext -> TypeEnv -> [AttrItem] -> InferM Type
inferRecAttrSet ctx env rawItems = do
  (items, dynamicEntries) <- normalizeAttrItems rawItems
  let fieldNames = [name | AttrField name _ <- items]
  placeholders <- Map.fromList <$> traverse (\name -> (,) name . Scheme [] <$> freshMeta) fieldNames
  let recEnv = placeholders <> env
      inferAttr = \case
        AttrField name expr -> do
          ty <- inferExpr ctx recEnv expr
          finalTy <- case Map.lookup name placeholders of
            Just scheme -> do
              expected <- instantiate scheme
              _ <- constrain ctx ty expected
              zonk expected
            Nothing -> pure ty
          pure [(name, finalTy)]
        AttrInherit names ->
          traverse (\name -> inferExpr ctx env (EVar name) >>= \ty -> pure (name, ty)) names
        AttrInheritFrom source names -> inferInheritFrom ctx recEnv source names
        AttrPath _ _ -> pure []
  fields <- concat <$> traverse inferAttr items
  case duplicateNames (map fst fields) of
    dup : _ -> throwCheck (withCode TC0002DuplicateAttribute ("duplicate attribute: " <> quoteName dup))
    [] -> do
      zonked <- Map.fromList <$> traverse (\(name, ty) -> (,) name <$> zonk ty) fields
      finishAttrSet ctx recEnv dynamicEntries zonked

-- | Bind the names introduced by a lambda pattern.
--
-- Attribute-set patterns produce a record argument type. Fields with a default
-- are checked against their (possibly annotated) field type; defaults may
-- refer to the other pattern names, as in Nix.
inferPatternBindings :: CheckContext -> TypeEnv -> Pattern -> InferM (Type, TypeEnv)
inferPatternBindings ctx env = \case
  PVar name ann -> do
    argTy <- maybe freshMeta pure ann
    pure (argTy, Map.singleton name (Scheme [] argTy))
  PAttrSet patternFields openPattern binder -> do
    let names = patternFieldNames patternFields <> maybe [] (pure . binderName) binder
        dups = duplicateNames names
    unless (null dups) (throwCheck (withCode TC0007DuplicatePatternBinding ("duplicate pattern bindings: " <> quoteNames dups)))
    fieldTys <- traverse (\field -> maybe freshSoftMeta pure (patternFieldType field)) patternFields
    rowTail <- freshMeta
    let markOptional field ty = if isJust (patternFieldDefault field) then TOptional ty else ty
        fields = Map.fromList [(patternFieldName field, markOptional field ty) | (field, ty) <- zip patternFields fieldTys]
        -- `...` admits further arguments, which the `@` binder may select.
        argTy = if openPattern then TOpenRecord fields rowTail else TRecord fields
        fieldEnv = Map.fromList (zip (patternFieldNames patternFields) (map (Scheme []) fieldTys))
        patternEnv = fieldEnv <> maybe Map.empty (\b -> Map.singleton (binderName b) (Scheme [] argTy)) binder
    forM_ (zip patternFields fieldTys) $ \(field, fieldTy) ->
      forM_ (patternFieldDefault field) $ \fallback -> do
        fallbackTy <- inferExpr ctx (patternEnv <> env) fallback
        -- `x ? null` is Nix's idiom for "optional": it says nothing about the
        -- type of a supplied value, so it does not constrain the field.
        unless (isNullLiteral fallback) $ do
        -- An unannotated defaulted argument takes the default's *widened*
        -- type: `b ? 2` accepts any Int, not just the literal 2.
          let target = if isJust (patternFieldType field) then fallbackTy else widenLiterals fallbackTy
          void (constrain ctx target fieldTy)
    pure (argTy, patternEnv)
  where
    binderName = \case
      BinderBefore name -> name
      BinderAfter name -> name

inferStaticSelect :: CheckContext -> Type -> Name -> InferM Type
inferStaticSelect ctx ty field =
  zonk ty >>= \resolvedTy ->
    let base' = resolveType (checkAliases ctx) resolvedTy
     in case base' of
          -- Selecting from a not-yet-known value: record the requirement as an
          -- open row, so later selections extend it (row polymorphism).
          TMeta n -> do
            fieldTy <- freshSoftMeta
            rowTail <- freshMeta
            _ <- bindMeta n (TOpenRecord (Map.singleton field fieldTy) rowTail)
            pure fieldTy
          TOpenRecord fields (TMeta n)
            | not (Map.member field fields) -> do
                fieldTy <- freshSoftMeta
                rowTail <- freshMeta
                _ <- bindMeta n (TOpenRecord (Map.singleton field fieldTy) rowTail)
                pure fieldTy
          _ -> inferStaticSelectKnown ctx resolvedTy base' field

inferStaticSelectKnown :: CheckContext -> Type -> Type -> Name -> InferM Type
inferStaticSelectKnown ctx resolvedTy base' field =
       if base' == tAny
          then pure tAny
          else
            if base' == tDynamic
              then pure tDynamic
              else
                if base' == tUnknown
                  then throwCheck (withCode TC0008SelectOnUnknown ("cannot select field " <> quoteName field <> " from unknown"))
                  else case lookupRecordField (checkAliases ctx) resolvedTy field of
                    Just fieldTy -> instantiate (schemeFromAnnotation fieldTy)
                    Nothing -> throwCheck (withCode TC0009MissingField ("missing field " <> quoteName field <> " on " <> showType resolvedTy))

inferDynamicSelect :: CheckContext -> Type -> Type -> InferM Type
inferDynamicSelect ctx baseTy keyTy = do
  resolvedBaseTy <- zonk baseTy
  resolvedKeyTy <- zonk keyTy
  let aliases = checkAliases ctx
      base' = resolveType aliases resolvedBaseTy
      key' = resolveType aliases resolvedKeyTy
  case () of
    _
      | base' == tAny || key' == tAny -> pure tAny
      | base' == tDynamic || key' == tDynamic || isMeta base' -> pure tDynamic
      | Just valueTy <- attrsOfView base' -> constrain ctx resolvedKeyTy tString *> pure valueTy
      | base' == tUnknown -> throwCheck (withCode TC0008SelectOnUnknown "cannot select dynamic field from unknown")
      | key' == tUnknown -> throwCheck (withCode TC0011DynamicKeyTypeMismatch "dynamic field selection expects a string-like key, but got unknown")
      | Just names <- selectionKeyNames key' ->
          case traverse (lookupRecordField aliases base') names of
            Just fieldTypes -> do
              instantiated <- traverse (instantiate . schemeFromAnnotation) fieldTypes
              case instantiated of
                x : xs -> pure (foldRight1 (joinTypes aliases) x xs)
                [] -> pure tDynamic
            Nothing -> throwCheck (withCode TC0010DynamicKeyMissingField ("missing field selected by dynamic key of type " <> showType key'))
      | isSubtype aliases key' tString || isConsistent aliases key' tString || isMeta key' -> pure tDynamic
      | otherwise -> throwCheck (withCode TC0012DynamicKeyNotStringLike ("dynamic field selection expects a string-like key, but got " <> showType key'))

isMeta :: Type -> Bool
isMeta = \case
  TMeta _ -> True
  _ -> False

selectionKeyNames :: Type -> Maybe [Name]
selectionKeyNames = \case
  TLit (LString name) -> Just [name]
  TUnion members -> concat <$> traverse selectionKeyNames members
  _ -> Nothing

-- | Generalize a type over the metas that do not occur free in @env@.
--
-- This is the Hindley-Milner `gen` step. Metas that also appear in the
-- environment belong to an enclosing binder (a lambda parameter, say) and must
-- stay shared, so only the remaining ones become quantified variables.
generalize :: TypeEnv -> Type -> InferM Scheme
generalize env ty = do
  subst <- gets substitutions
  let zonked = substituteMetas subst ty
      envMetas = foldMap (freeMetas . substituteMetas subst . schemeType) (Map.elems env)
      quantifiable = sort (Set.toList (freeMetas zonked `Set.difference` envMetas))
      taken = freeTypeVars zonked
      names = take (length quantifiable) [name | i <- [0 :: Int ..], let name = T.pack ("t" <> show i), not (Set.member name taken)]
      renaming = Map.fromList (zip quantifiable (TVar <$> names))
  pure (Scheme names (substituteMetas renaming zonked))

-- | Names a binding's expression refers to (an over-approximation that
-- ignores shadowing), used to order `let` bindings by dependency.
exprFreeNames :: Expr -> Set.Set Name
exprFreeNames = go
  where
    go = \case
      EVar name -> Set.singleton name
      ELoc _ inner -> go inner
      ELambda pat body -> goPat pat <> go body
      EApp f x -> go f <> go x
      EBinaryOp _ l r -> go l <> go r
      EUnaryOp _ x -> go x
      ELet items body -> foldMap (goLet . markedValue) items <> go body
      EAttrSet items -> foldMap goAttr items
      ERec items -> foldMap goAttr items
      ESelect base steps -> go base <> foldMap goStep steps
      ESelectOr base steps def -> go base <> foldMap goStep steps <> go def
      EHasAttr base steps -> go base <> foldMap goStep steps
      EAssert c b -> go c <> go b
      EWith sc b -> go sc <> go b
      EIf c a b -> go c <> go a <> go b
      EList xs -> foldMap go xs
      ECast e _ -> go e
      EInterp _ parts -> foldMap goPart parts
      EPathInterp parts -> foldMap goPart parts
      _ -> Set.empty
    goPart = \case
      StrExpr e -> go e
      _ -> Set.empty
    goStep = \case
      SelectDynamic e -> go e
      SelectName _ -> Set.empty
    goPat = \case
      PAttrSet fields _ _ -> foldMap (foldMap go . patternFieldDefault) fields
      PVar _ _ -> Set.empty
    goLet = \case
      LetBinding _ e -> go e
      LetInherit (Just src) _ -> go src
      LetInherit Nothing names -> Set.fromList names
      LetPath steps e -> foldMap goStep steps <> go e
      LetSignature _ _ -> Set.empty
    goAttr = \case
      AttrField _ e -> go e
      AttrInherit names -> Set.fromList names
      AttrInheritFrom src _ -> go src
      AttrPath steps e -> foldMap goStep steps <> go e

-- | Instantiate a polymorphic scheme by replacing quantified variables with
-- fresh inference metas.
instantiate :: Scheme -> InferM Type
instantiate (Scheme vars ty) = do
  reps <- traverse (const freshMeta) vars
  pure (substituteTypeVars (Map.fromList (zip vars reps)) ty)

-- | Allocate a fresh soft meta (see 'InferState').
freshSoftMeta :: InferM Type
freshSoftMeta = do
  meta <- freshMeta
  case meta of
    TMeta n -> modify' (\st -> st{softMetas = Set.insert n (softMetas st)})
    _ -> pure ()
  pure meta

isSoftMeta :: Int -> InferM Bool
isSoftMeta n = gets (Set.member n . softMetas)

-- | Allocate a fresh inference meta variable.
freshMeta :: InferM Type
freshMeta = do
  st <- get
  put st{nextMeta = nextMeta st + 1}
  pure (TMeta (nextMeta st))

-- | Apply the current substitution set to a type.
--
-- This is the main "read your work back" operation of the inference engine:
-- callers use it after unification or binding a meta to recover the most
-- up-to-date structural view.
zonk :: Type -> InferM Type
zonk ty = substituteMetas <$> gets substitutions <*> pure ty

inferRootExpression :: CheckContext -> TypeEnv -> Marked Expr -> InferM CheckResult
inferRootExpression ctx env (Marked directive expr) = do
  attempt <-
    catchInfer $
      case unloc expr of
        ELet items body -> do
          (env', bindings) <- inferLet ctx env items
          ty <- inferExpr ctx env' body >>= zonk
          displayed <- traverse displayScheme bindings
          pure (CheckResult (Just (hideSingletonRows (closeMetas ty))) displayed)
        _ -> do
          ty <- inferExpr ctx env expr >>= zonk
          pure (CheckResult (Just (hideSingletonRows (closeMetas ty))) Map.empty)
  case (directive, attempt) of
    (Nothing, Right result) -> pure result
    (Nothing, Left err) -> lift (Left err)
    (Just TnixIgnore, Right result) -> pure result
    (Just TnixIgnore, Left _) -> pure (CheckResult (Just (Scheme [] tDynamic)) Map.empty)
    (Just TnixExpected, Left _) -> pure (CheckResult (Just (Scheme [] tDynamic)) Map.empty)
    (Just TnixExpected, Right _) -> throwCheck (withCode TC0006UnusedExpectedDirective "unused @tnix-expected directive on root expression")

-- | Zonk a binding's scheme after the whole program has been solved and close
-- any metas that are still open, for stable user-facing output.
displayScheme :: Scheme -> InferM Scheme
displayScheme (Scheme vars ty) = do
  zonked <- zonk ty
  let metas = sort (Set.toList (freeMetas zonked))
      taken = Set.fromList vars <> freeTypeVars zonked
      names = take (length metas) [name | i <- [0 :: Int ..], let name = T.pack ("t" <> show i), not (Set.member name taken)]
  pure (hideSingletonRows (Scheme (vars <> names) (substituteMetas (Map.fromList (zip metas (TVar <$> names))) zonked)))

-- | A row variable that occurs only once in a scheme carries no information
-- ("some further fields"), so it is displayed as a plain `...`.
hideSingletonRows :: Scheme -> Scheme
hideSingletonRows (Scheme vars ty) =
  let counts = occurrences ty
      single name = Map.findWithDefault 0 name counts == (1 :: Int)
      hide = \case
        TOpenRecord fields (TVar name) | single name -> TOpenRecord (fmap hide fields) TDynamic
        TOpenRecord fields tail' -> TOpenRecord (fmap hide fields) (hide tail')
        TRecord fields -> TRecord (fmap hide fields)
        TFun mult a b -> TFun mult (hide a) (hide b)
        TApp f x -> TApp (hide f) (hide x)
        TUnion members -> TUnion (map hide members)
        TOptional inner -> TOptional (hide inner)
        TTypeList items -> TTypeList (map hide items)
        other -> other
      hidden = hide ty
   in Scheme (filter (`Set.member` freeTypeVars hidden) vars) hidden
  where
    occurrences = \case
      TVar name -> Map.singleton name 1
      TOpenRecord fields tail' -> Map.unionsWith (+) (occurrences tail' : map occurrences (Map.elems fields))
      TRecord fields -> Map.unionsWith (+) (map occurrences (Map.elems fields))
      TFun _ a b -> Map.unionWith (+) (occurrences a) (occurrences b)
      TApp f x -> Map.unionWith (+) (occurrences f) (occurrences x)
      TUnion members -> Map.unionsWith (+) (map occurrences members)
      TOptional inner -> occurrences inner
      TTypeList items -> Map.unionsWith (+) (map occurrences items)
      _ -> Map.empty

catchInfer :: InferM a -> InferM (Either CheckError a)
catchInfer action = do
  snapshot <- get
  case runStateT action snapshot of
    Left err -> pure (Left err)
    Right (value, state') -> put state' >> pure (Right value)

recoverSuppressedType :: CheckContext -> Type -> InferM Type
recoverSuppressedType ctx expected = constrain ctx tDynamic expected *> zonk expected

-- | Check that an inferred type satisfies an expected type.
--
-- Compared with `unify`, `constrain` is intentionally directional. It is used
-- for user annotations and function arguments where one side represents an
-- obligation rather than an unknown peer.
--
-- A few policy choices are important here:
--
-- * exact subtyping succeeds immediately,
-- * gradual consistency is only accepted when `dynamic` participates,
-- * plain concrete mismatches do /not/ fall through to permissive unification,
-- * sequence types may compare through their structural `List` view when one
--   side explicitly asks for `List`.
--
-- Representative examples:
--
-- @
-- constrain (Vec 2 Int) (List Int)
--   => succeeds through the structural list view
--
-- constrain (Vec 3 Int) (Vec (2 | Range 4 8 Nat) Int)
--   => fails
--
-- constrain dynamic String
--   => succeeds, because the mismatch is genuinely gradual
-- @
constrain :: CheckContext -> Type -> Type -> InferM Type
constrain ctx actual expected = do
  actual' <- normalizeIndexedType <$> zonk actual
  expected' <- normalizeIndexedType <$> zonk expected
  case (actual', expected') of
    _
      | Just actualList <- sequenceListView actual',
        isPlainListType expected' ->
          constrain ctx actualList expected'
      | isPlainListType actual',
        Just expectedList <- sequenceListView expected' ->
          constrain ctx actual' expectedList
    (TMeta n, TMeta m) | n == m -> pure actual'
    -- Passing a still-unknown value where *anything* (or any attribute set)
    -- is accepted must not pin it to that top type: `builtins.hasAttr k x`
    -- says nothing about the rest of `x`.
    (TMeta _, TUnknown) -> pure expected'
    (TMeta n, TApp (TCon "AttrsOf") TUnknown) -> do
      rowTail <- freshMeta
      _ <- bindMeta n (TOpenRecord Map.empty rowTail)
      pure expected'
    (TMeta n, ty) -> bindMeta n ty
    (ty, TMeta n) -> bindMeta n ty
    (TTypeList xs, TTypeList ys)
      | length xs == length ys ->
          TTypeList <$> zipWithM (constrain ctx) xs ys
    (TFun actualMult actualArg actualResult, TFun expectedMult expectedArg expectedResult)
      | multiplicitySubtype actualMult expectedMult ->
          TFun expectedMult <$> constrain ctx expectedArg actualArg <*> constrain ctx actualResult expectedResult
    (TOptional a, TOptional b) -> TOptional <$> constrain ctx a b
    _
      | hasUnresolvedMetas actual' expected',
        Just (actualFields, actualTail) <- recordView (resolveType (checkAliases ctx) actual'),
        Just (expectedFields, _) <- recordView (resolveType (checkAliases ctx) expected') ->
          constrainRecord ctx actualFields actualTail expectedFields $> expected'
      | hasUnresolvedMetas actual' expected',
        Just (actualFields, _) <- recordView (resolveType (checkAliases ctx) actual'),
        Just valueTy <- attrsOfView (resolveType (checkAliases ctx) expected') ->
          -- A record used as a dictionary: its values must fit together, so
          -- their join (not the first field) determines the value type.
          case map unOptional (Map.elems actualFields) of
            [] -> pure expected'
            x : xs -> do
              first <- zonk x
              rest <- traverse zonk xs
              let joined = foldRight1 (joinTypes (checkAliases ctx)) first rest
              constrain ctx (widenLiterals joined) valueTy $> expected'
    _ | actual' == expected' -> pure expected'
    _ | isSubtype (checkAliases ctx) actual' expected' -> pure expected'
    _ | allowsGradualConsistency actual' expected' && isConsistent (checkAliases ctx) actual' expected' -> pure expected'
    _ | hasUnresolvedMetas actual' expected' -> unify ctx actual' expected'
    _
      | Just detail <- recordMismatchDetail (checkAliases ctx) actual' expected' -> throwCheck detail
    _ -> throwCheck (withCode TC0013TypeMismatch ("type mismatch: " <> showType actual' <> " vs " <> showType expected'))

-- | Explain why one record does not satisfy another: the first missing
-- required field, or the first field whose type does not fit.
recordMismatchDetail :: AliasEnv -> Type -> Type -> Maybe String
recordMismatchDetail aliases actual expected = do
  (actualFields, actualTail) <- recordView (resolveType aliases actual)
  (expectedFields, _) <- recordView (resolveType aliases expected)
  let open = actualTail == Just tDynamic || actualTail == Just tAny
      missing =
        [ name
          | (name, ty) <- Map.toList expectedFields,
            not (isOptionalField ty),
            not (Map.member name actualFields),
            not open
        ]
      wrong =
        [ (name, unOptional a, unOptional e)
          | (name, e) <- Map.toList expectedFields,
            Just a <- [Map.lookup name actualFields],
            not (isSubtype aliases (unOptional a) (unOptional e))
        ]
  case (missing, wrong) of
    (name : _, _) ->
      Just (withCode TC0009MissingField ("missing field " <> quoteName name <> ": expected " <> showType expected <> " but got " <> showType actual))
    ([], (name, a, e) : _) ->
      Just (withCode TC0013TypeMismatch ("type mismatch in field " <> quoteName name <> ": " <> showType a <> " vs " <> showType e))
    _ -> Nothing
  where
    isOptionalField = \case
      TOptional _ -> True
      _ -> False

-- | Width-subtyping obligation between record shapes that still contain
-- metas: every expected field must be provided (unless optional). A missing
-- field extends the actual row when its tail is still open.
constrainRecord :: CheckContext -> Map Name Type -> Maybe Type -> Map Name Type -> InferM ()
constrainRecord ctx actualFields actualTail expectedFields =
  forM_ (Map.toList expectedFields) $ \(name, expectedTy) ->
    case Map.lookup name actualFields of
      Just actualTy -> void (constrain ctx (unOptional actualTy) (unOptional expectedTy))
      Nothing ->
        case expectedTy of
          TOptional _ -> pure ()
          _ -> do
            tail' <- traverse zonk actualTail
            case tail' of
              Just (TMeta n) -> do
                rowTail <- freshMeta
                void (bindMeta n (TOpenRecord (Map.singleton name expectedTy) rowTail))
              Just ty | ty == tDynamic || ty == tAny -> pure ()
              _ -> throwCheck (withCode TC0009MissingField ("missing field " <> quoteName name <> " required by " <> showType (TRecord expectedFields)))

-- | Symmetric structural unification used while solving metas.
--
-- Unlike `constrain`, both sides are treated as peers here. When metas are
-- present the function may bind them, recursively unify structured types, or
-- join gradually consistent shapes when `dynamic` is involved.
--
-- Representative examples:
--
-- @
-- unify ?0 Int
--   => binds ?0 := Int
--
-- unify (List ?0) (List String)
--   => binds ?0 := String
--
-- unify Int String
--   => fails
-- @
unify :: CheckContext -> Type -> Type -> InferM Type
unify ctx left right = do
  left' <- normalizeIndexedType <$> zonk left
  right' <- normalizeIndexedType <$> zonk right
  case (left', right') of
    _
      | Just leftList <- sequenceListView left',
        isPlainListType right' ->
          unify ctx leftList right'
      | isPlainListType left',
        Just rightList <- sequenceListView right' ->
          unify ctx left' rightList
    (TMeta n, TMeta m) | n == m -> pure left'
    (TMeta n, ty) -> bindMeta n ty
    (ty, TMeta n) -> bindMeta n ty
    (TTypeList xs, TTypeList ys)
      | length xs == length ys ->
          TTypeList <$> zipWithM (unify ctx) xs ys
    -- Two exact sequence shapes that disagree (a 1-element and a 3-element
    -- list literal, say) meet at their common `List` view.
    _
      | Just leftList <- sequenceListView left',
        Just rightList <- sequenceListView right',
        hasUnresolvedMetas left' right' || not (isSubtype (checkAliases ctx) left' right' || isSubtype (checkAliases ctx) right' left') ->
          unify ctx leftList rightList
    (TFun leftMult a b, TFun rightMult c d)
      | leftMult == rightMult ->
          TFun leftMult <$> unify ctx a c <*> unify ctx b d
    (TRecord a, TRecord b) -> unifyRecord a b
    _
      | Just (a, ta) <- recordView left',
        Just (b, tb) <- recordView right',
        isJust ta || isJust tb ->
          unifyRows left' right' a ta b tb
    (TOptional a, TOptional b) -> TOptional <$> unify ctx a b
    (TApp f x, TApp g y) -> TApp <$> unify ctx f g <*> unify ctx x y
    _ | left' == right' -> pure left'
    _ | isSubtype (checkAliases ctx) left' right' -> pure right'
    _ | isSubtype (checkAliases ctx) right' left' -> pure left'
    _ | allowsGradualConsistency left' right' && isConsistent (checkAliases ctx) left' right' -> pure (joinTypes (checkAliases ctx) left' right')
    _ -> throwCheck (withCode TC0013TypeMismatch ("type mismatch: " <> showType left' <> " vs " <> showType right'))
  where
    -- Rows unify field-wise on their common labels; each side's tail absorbs
    -- the labels only the other side has, sharing one fresh rest-row.
    unifyRows leftTy rightTy a ta b tb = do
      _ <- sequence (Map.intersectionWith (unify ctx) a b)
      let onlyA = Map.difference a b
          onlyB = Map.difference b a
      case (ta, tb) of
        (Nothing, Just tailB)
          | Map.null onlyB -> unify ctx tailB (TRecord onlyA) *> zonk leftTy
        (Just tailA, Nothing)
          | Map.null onlyA -> unify ctx tailA (TRecord onlyB) *> zonk rightTy
        (Just tailA, Just tailB) -> do
          rest <- freshMeta
          _ <- unify ctx tailA (mkOpenRecord onlyB rest)
          _ <- unify ctx tailB (mkOpenRecord onlyA rest)
          zonk leftTy
        _ -> throwCheck (withCode TC0014RecordMismatch ("record mismatch: " <> showType leftTy <> " vs " <> showType rightTy))
    unifyRecord a b
      | Map.keysSet b `Set.isSubsetOf` Map.keysSet a =
          Map.traverseWithKey (\name bTy -> maybe (pure bTy) (\aTy -> unify ctx aTy bTy) (Map.lookup name a)) b
            <&> TRecord
      | Map.keysSet a `Set.isSubsetOf` Map.keysSet b =
          Map.traverseWithKey (\name aTy -> maybe (pure aTy) (unify ctx aTy) (Map.lookup name b)) a
            <&> TRecord
      | otherwise = throwCheck (withCode TC0014RecordMismatch ("record mismatch: " <> showRecord a <> " vs " <> showRecord b))

-- | Bind one inference meta to a solved type, performing the occurs check.
bindMeta :: Int -> Type -> InferM Type
bindMeta n ty = do
  resolved <- zonk ty
  when (resolved == TMeta n || n `Set.member` freeMetas resolved) (throwCheck (withCode TC0016OccursCheckFailed "occurs check failed"))
  modify' (\st -> st{substitutions = Map.insert n resolved (substitutions st)})
  pure resolved

-- | Validate an explicit `expr as Type` assertion.
--
-- Casts deliberately live between plain assignment and fully-unsound escape
-- hatches. They are accepted when the two sides already overlap structurally,
-- when a gradual boundary such as `any`, `unknown`, or `dynamic` connects
-- them, or when the cast still contains unresolved inference metas that can be
-- solved by unification.
--
-- Representative examples:
--
-- @
-- { value = 1; } as { value :: Int; }
--   => accepted
--
-- import ./opaque.nix as { value :: String; }
--   => accepted when the import is `dynamic`
--
-- 1 as String
--   => rejected
-- @
checkCast :: CheckContext -> Type -> Type -> InferM Type
checkCast ctx actual expected = do
  actual' <- normalizeIndexedType <$> zonk actual
  expected' <- normalizeIndexedType <$> zonk expected
  let aliases = checkAliases ctx
  if hasUnresolvedMetas actual' expected'
    then unify ctx actual' expected' $> expected
    else
      if isSubtype aliases actual' expected'
        || isSubtype aliases expected' actual'
        || isConsistent aliases actual' expected'
        then pure expected
        else throwCheck (withCode TC0015InvalidCast ("invalid cast: " <> showType actual' <> " as " <> showType expected'))

-- | Infer the result type of a binary operator application.
--
-- Numeric `+` keeps its dedicated coercion rules; structural equality accepts
-- any operands and yields `Bool`; ordered comparisons require comparable
-- (numeric or string) operands; boolean connectives require `Bool` operands.
inferBinaryOp :: CheckContext -> TypeEnv -> BinOp -> Expr -> Expr -> InferM Type
inferBinaryOp ctx env op left right =
  case op of
    OpAdd -> inferArithmetic ctx env op left right
    OpSub -> inferArithmetic ctx env op left right
    OpMul -> inferArithmetic ctx env op left right
    OpConcat -> inferConcat ctx env left right
    OpUpdate -> inferUpdate ctx env left right
    OpEq -> inferEquality ctx env left right
    OpNeq -> inferEquality ctx env left right
    OpLt -> inferRelational ctx env left right
    OpGt -> inferRelational ctx env left right
    OpLe -> inferRelational ctx env left right
    OpGe -> inferRelational ctx env left right
    OpAnd -> inferLogical ctx env left right
    OpOr -> inferLogical ctx env left right
    OpImpl -> inferLogical ctx env left right
    OpDiv -> inferArithmetic ctx env op left right
    OpPipeRight -> inferExpr ctx env (EApp right left)
    OpPipeLeft -> inferExpr ctx env (EApp left right)

inferArithmetic :: CheckContext -> TypeEnv -> BinOp -> Expr -> Expr -> InferM Type
inferArithmetic ctx env op left right = do
  leftTy <- inferExpr ctx env left >>= zonk
  rightTy <- inferExpr ctx env right >>= zonk
  let aliases = checkAliases ctx
      leftResolved = resolveType aliases leftTy
      rightResolved = resolveType aliases rightTy
  if leftResolved == tAny || rightResolved == tAny
    then pure tAny
    else
      if leftResolved == tDynamic || rightResolved == tDynamic
        then pure tDynamic
        else case textConcatTarget aliases op leftResolved rightResolved of
          -- `+` also concatenates strings and paths, as in Nix.
          Just (leftExpected, rightExpected, result) -> do
            _ <- constrain ctx leftTy leftExpected
            _ <- constrain ctx rightTy rightExpected
            pure result
          Nothing -> do
            let expected = arithmeticTarget op leftResolved rightResolved
            _ <- constrain ctx leftTy expected
            _ <- constrain ctx rightTy expected
            zonk expected

-- | Decide whether `+` is string/path concatenation. The result follows the
-- left operand: `path + string` is a path, `string + path` a string.
textConcatTarget :: AliasEnv -> BinOp -> Type -> Type -> Maybe (Type, Type, Type)
textConcatTarget aliases op left right
  | op /= OpAdd = Nothing
  | isPathLike left, isTextLike right || isMeta right = Just (tPath, tString `orPath` right, tPath)
  | isStringLike left, isTextLike right || isMeta right = Just (tString, tString `orPath` right, tString)
  | isMeta left, isStringLike right = Just (tString, tString, tString)
  | isMeta left, isPathLike right = Just (tPath, tPath, tPath)
  | otherwise = Nothing
  where
    isStringLike ty = isSubtype aliases ty tString
    isPathLike ty = isSubtype aliases ty tPath
    isTextLike ty = isStringLike ty || isPathLike ty
    orPath base ty = if isPathLike ty then tPath else base

-- | Pick the numeric result family for an arithmetic operator. Subtraction can
-- yield negative results, so a `Nat`-only operand pair widens to `Int`.
arithmeticTarget :: BinOp -> Type -> Type -> Type
arithmeticTarget op left right =
  let base = additionTarget left right
   in if op == OpSub && base == tNat then tInt else base

-- | Structural equality (`==`/`!=`) accepts any pair of operands and always
-- produces `Bool`, mirroring Nix's value-level equality.
inferEquality :: CheckContext -> TypeEnv -> Expr -> Expr -> InferM Type
inferEquality ctx env left right = do
  _ <- inferExpr ctx env left
  _ <- inferExpr ctx env right
  pure tBool

-- | Ordered comparisons require comparable operands (numeric or string) on both
-- sides, unless a gradual boundary connects them. The result is always `Bool`.
inferRelational :: CheckContext -> TypeEnv -> Expr -> Expr -> InferM Type
inferRelational ctx env left right = do
  leftTy <- inferExpr ctx env left >>= zonk
  rightTy <- inferExpr ctx env right >>= zonk
  let aliases = checkAliases ctx
      leftResolved = resolveType aliases leftTy
      rightResolved = resolveType aliases rightTy
      gradual ty = ty == tAny || ty == tDynamic
      comparable ty = isSubtype aliases ty tNumber || isSubtype aliases ty tString || isSubtype aliases ty tPath
      comparisonBase ty
        | isSubtype aliases ty tNumber = tNumber
        | isSubtype aliases ty tPath = tPath
        | otherwise = tString
  if gradual leftResolved || gradual rightResolved || (comparable leftResolved && comparable rightResolved)
    then pure tBool
    else if isMeta leftResolved && comparable rightResolved
      then constrain ctx leftTy (comparisonBase rightResolved) $> tBool
    else if isMeta rightResolved && comparable leftResolved
      then constrain ctx rightTy (comparisonBase leftResolved) $> tBool
    else if hasUnresolvedMetas leftResolved rightResolved
      then pure tBool
    else
      throwCheck
            ( withCode
                TC0019NotComparable
                ("cannot compare " <> showType leftResolved <> " with " <> showType rightResolved)
            )

-- | Boolean connectives (`&&`/`||`) require `Bool` operands and yield `Bool`.
inferLogical :: CheckContext -> TypeEnv -> Expr -> Expr -> InferM Type
inferLogical ctx env left right = do
  leftTy <- inferExpr ctx env left
  _ <- constrain ctx leftTy tBool
  rightTy <- inferExpr ctx env right
  _ <- constrain ctx rightTy tBool
  pure tBool

-- | List concatenation (`++`) requires list-like operands on both sides and
-- produces a plain @List@ whose element type joins the two element types.
-- Fixed-shape sequences (vectors, tuples) participate via their structural
-- list view; precise length information is intentionally not tracked here.
inferConcat :: CheckContext -> TypeEnv -> Expr -> Expr -> InferM Type
inferConcat ctx env left right = do
  leftTy <- inferExpr ctx env left >>= zonk
  rightTy <- inferExpr ctx env right >>= zonk
  let aliases = checkAliases ctx
      leftResolved = resolveType aliases leftTy
      rightResolved = resolveType aliases rightTy
  if leftResolved == tAny || rightResolved == tAny
    then pure tAny
    else
      if leftResolved == tDynamic || rightResolved == tDynamic
        then pure tDynamic
        else do
         left' <- listIfMeta leftResolved
         right' <- listIfMeta rightResolved
         case (listElementType left', listElementType right') of
          (Just leftElem, Just rightElem) -> do
            leftElem' <- zonk leftElem
            rightElem' <- zonk rightElem
            if hasUnresolvedMetas leftElem' rightElem'
              then tList <$> joinBranches ctx leftElem' rightElem'
              else pure (tList (joinTypes aliases leftElem' rightElem'))
          _ | hasUnresolvedMetas left' right' -> pure tDynamic
          _ ->
            throwCheck
                  ( withCode
                      TC0020NotConcatenable
                      ("cannot concatenate " <> showType leftResolved <> " with " <> showType rightResolved)
                  )

-- | Attribute-set update (`//`) merges two record types, with the right-hand
-- side overriding fields present on both. A gradual operand on either side
-- yields a gradual result; non-record operands raise TC0021.
inferUpdate :: CheckContext -> TypeEnv -> Expr -> Expr -> InferM Type
inferUpdate ctx env left right = do
  leftTy <- inferExpr ctx env left >>= zonk
  rightTy <- inferExpr ctx env right >>= zonk
  let aliases = checkAliases ctx
      leftResolved = resolveType aliases leftTy
      rightResolved = resolveType aliases rightTy
  if leftResolved == tAny || rightResolved == tAny
    then pure tAny
    else
      if leftResolved == tDynamic || rightResolved == tDynamic
        then pure tDynamic
        else do
          left' <- openIfMeta leftResolved
          right' <- openIfMeta rightResolved
          case (left', right') of
            _
              | Just (leftFields, leftTail) <- recordView left',
                Just (rightFields, rightTail) <- recordView right' ->
                  -- Right-hand fields win. An open right side may override any
                  -- left field with an unknown type, so its row stays open.
                  pure $ case (leftTail, rightTail) of
                    (Nothing, Nothing) -> TRecord (Map.union rightFields leftFields)
                    (_, Just tail') -> mkOpenRecord (Map.union rightFields leftFields) tail'
                    (Just tail', Nothing) -> mkOpenRecord (Map.union rightFields leftFields) tail'
              | Just leftValue <- attrsOfView left',
                Just rightValue <- attrsOfView right' ->
                  pure (tAttrsOf (joinTypes aliases leftValue rightValue))
              | Just leftValue <- attrsOfView left',
                Just (rightFields, _) <- recordView right' ->
                  pure (tAttrsOf (foldr (joinTypes aliases . unOptional) leftValue (Map.elems rightFields)))
              | Just (leftFields, _) <- recordView left',
                Just rightValue <- attrsOfView right' ->
                  pure (tAttrsOf (foldr (joinTypes aliases . unOptional) rightValue (Map.elems leftFields)))
              -- A shape that is still partly unknown (say, a union with an
              -- unsolved member) cannot be judged yet; stay gradual.
              | hasUnresolvedMetas left' right' -> pure tDynamic
            _ ->
              throwCheck
                ( withCode
                    TC0021NotUpdatable
                    ("cannot update " <> showType leftResolved <> " with " <> showType rightResolved)
                )

-- | A `++` operand whose type is still unknown must be a list.
listIfMeta :: Type -> InferM Type
listIfMeta = \case
  TMeta n -> do
    elemTy <- freshMeta
    bindMeta n (tList elemTy)
  other -> pure other

-- | An attribute-set operand whose type is still unknown becomes an open row,
-- so `//` can proceed and later uses refine it.
openIfMeta :: Type -> InferM Type
openIfMeta = \case
  TMeta n -> do
    rowTail <- freshMeta
    bindMeta n (TOpenRecord Map.empty rowTail)
  other -> pure other

-- | Extract the element type of a list-like type: a plain @List a@ directly,
-- or any fixed-shape sequence (vector, tuple) via its structural list view.
listElementType :: Type -> Maybe Type
listElementType ty =
  case plainListElement ty of
    Just elemTy -> Just elemTy
    Nothing -> sequenceListView ty >>= plainListElement
  where
    plainListElement candidate =
      case collectApps candidate of
        (TCon "List", [elemTy]) -> Just elemTy
        _ -> Nothing

additionTarget :: Type -> Type -> Type
additionTarget left right =
  case (numericFamily left, numericFamily right) of
    (Just leftBase, Just rightBase) -> joinNumericFamilies leftBase rightBase
    (Just knownBase, Nothing)
      | hasUnresolvedMetas left right -> widenSingleNumericFamily knownBase
    (Nothing, Just knownBase)
      | hasUnresolvedMetas left right -> widenSingleNumericFamily knownBase
    _ -> tNumber

numericFamily :: Type -> Maybe Type
numericFamily = \case
  ty
    | ty == tNat -> Just tNat
    | ty == tInt -> Just tInt
    | ty == tFloat -> Just tFloat
    | ty == tNumber -> Just tNumber
  TLit (LInt _) -> Just tInt
  TLit (LFloat _) -> Just tFloat
  _ -> Nothing

joinNumericFamilies :: Type -> Type -> Type
joinNumericFamilies left right
  | left == right = left
  | left == tNat, right == tInt = tInt
  | left == tInt, right == tNat = tInt
  | otherwise = tNumber

widenSingleNumericFamily :: Type -> Type
widenSingleNumericFamily ty
  | ty == tNat = tInt
  | ty == tInt = tInt
  | otherwise = tNumber

-- | Resolve an import path relative to the current source file.
--
-- Absolute paths are normalized but otherwise preserved. Relative paths are
-- interpreted against the directory containing the current file, mirroring how
-- Nix imports behave.
resolvePath :: FilePath -> FilePath -> FilePath
resolvePath from target
  | isAbsolute target = collapseParentSegments target
  | otherwise = collapseParentSegments (takeDirectory from </> target)

-- | Normalize `.` and `..` path segments without escaping an absolute root.
--
-- Segments accumulate in reverse so the most recent one is the head of the
-- list: dropping a segment for `..` is then O(1) instead of the O(n) reverse
-- and append the forward-ordered version needed on every step.
collapseParentSegments :: FilePath -> FilePath
collapseParentSegments = joinPath . reverse . foldl step [] . splitDirectories . normalise
  where
    step acc "." = acc
    step acc ".." =
      case acc of
        [] -> [".."]
        [root] | isAbsoluteRoot root -> acc
        _ : rest -> rest
    step acc part = part : acc
    isAbsoluteRoot part = part == "/"

duplicateNames :: (Ord a) => [a] -> [a]
duplicateNames = foldr step [] . group . sort
  where
    step xs acc =
      case xs of
        first : _ | length xs > 1 -> first : acc
        _ -> acc

-- | Render a name inside backticks so diagnostics stay readable.
quoteName :: Name -> String
quoteName name = "`" <> T.unpack name <> "`"

-- | Types that can never be applied as a function. Deliberately conservative:
-- only structurally-concrete non-functions (literals, records, lists, and the
-- base scalar constructors) are flagged. Gradual types (dynamic, any, unknown),
-- unresolved metas, and type applications fall through so the gradual boundary
-- and inference behavior are preserved.
definitelyNotCallable :: Type -> Bool
definitelyNotCallable ty = case ty of
  TLit _ -> True
  TRecord _ -> True
  TTypeList _ -> True
  TCon name -> name `elem` ["String", "Int", "Float", "Number", "Nat", "Bool", "Null", "Path"]
  _ -> False

-- | Human-readable noun phrase for a non-callable value, used in TC0018.
describeNonCallable :: Type -> String
describeNonCallable ty = case ty of
  TRecord _ -> "an attribute set"
  TTypeList _ -> "a list"
  TLit (LString _) -> "a string"
  TLit (LInt _) -> "an integer"
  TLit (LFloat _) -> "a float"
  TLit (LBool _) -> "a boolean"
  TCon name -> "a value of type " <> T.unpack name
  _ -> "a non-function value"

-- | Render a list of names as a comma-separated, backtick-quoted sequence.
quoteNames :: [Name] -> String
quoteNames = intercalate ", " . map quoteName

-- | Render a type using the surface syntax produced by 'Pretty'.
showType :: Type -> String
showType = T.unpack . T.unwords . map T.strip . T.lines . renderType

-- | Render a record's field map as the equivalent record type.
showRecord :: Map Name Type -> String
showRecord = showType . TRecord

-- | Infer a lambda's multiplicity from its body usage count.
--
-- A binder used exactly once becomes linear; anything else becomes
-- unrestricted. This is intentionally local and syntactic.
inferLambdaMultiplicity :: Pattern -> Expr -> Multiplicity
inferLambdaMultiplicity pattern' body =
  case pattern' of
    PVar name _ | usageCount name body == 1 -> One
    _ -> Many

-- | Count syntactic occurrences of a binder in an expression.
--
-- Shadowing stops the walk for the shadowed name, and recursive `let`
-- definitions are treated conservatively by not counting occurrences through a
-- re-bound name.
usageCount :: Name -> Expr -> Int
usageCount target = go
  where
    go = \case
      EVar name
        | name == target -> 1
        | otherwise -> 0
      EString _ -> 0
      EInterp _ parts -> sum [go expr | StrExpr expr <- parts]
      EFloat _ -> 0
      EInt _ -> 0
      EBool _ -> 0
      ENull -> 0
      EPath _ -> 0
      ESearchPath _ -> 0
      EPathInterp parts -> sum [go expr | StrExpr expr <- parts]
      ELoc _ inner -> go inner
      ESelectOr base steps fallback -> go base + sum (map selectStepCount steps) + go fallback
      ELambda pattern' body
        | target `elem` patternBoundNames pattern' -> 0
        | otherwise -> go body
      EApp fun arg -> go fun + go arg
      EBinaryOp _ left right -> go left + go right
      EUnaryOp _ operand -> go operand
      ELet items body ->
        let names = concatMap (letBoundNames . markedValue) items
         in if target `elem` names
              then 0
              else sum (map (letItemCount . markedValue) items) + go body
      EAttrSet items -> sum (map attrItemCount items)
      ERec items ->
        if target `elem` concatMap attrBoundNames items
          then 0
          else sum (map attrItemCount items)
      ESelect base steps -> go base + sum (map selectStepCount steps)
      EHasAttr base steps -> go base + sum (map selectStepCount steps)
      EIf cond yesExpr noExpr -> go cond + max (go yesExpr) (go noExpr)
      EAssert cond body -> go cond + go body
      EWith scope body -> go scope + go body
      EList items -> sum (map go items)
      ECast expr _ -> go expr
    letItemCount = \case
      LetSignature _ _ -> 0
      LetBinding _ expr -> go expr
      LetInherit source names -> maybe (length (filter (== target) names)) go source
      LetPath steps expr -> sum (map selectStepCount steps) + go expr
    attrItemCount = \case
      AttrField _ expr -> go expr
      AttrInherit names -> length (filter (== target) names)
      AttrInheritFrom source _ -> go source
      AttrPath steps expr -> sum (map selectStepCount steps) + go expr
    letBoundNames = \case
      LetBinding name _ -> [name]
      LetPath (SelectName name : _) _ -> [name]
      LetInherit _ names -> names
      _ -> []
    attrBoundNames = \case
      AttrField name _ -> [name]
      AttrPath (SelectName name : _) _ -> [name]
      AttrInherit names -> names
      AttrInheritFrom _ names -> names
      _ -> []
    selectStepCount = \case
      SelectName _ -> 0
      SelectDynamic expr -> go expr

patternBoundNames :: Pattern -> [Name]
patternBoundNames = \case
  PVar name _ -> [name]
  PAttrSet fields _ binder -> patternFieldNames fields <> maybe [] (pure . binderName) binder
  where
    binderName = \case
      BinderBefore name -> name
      BinderAfter name -> name

multiplicitySubtype :: Multiplicity -> Multiplicity -> Bool
multiplicitySubtype actual expected =
  actual == expected
    || case (actual, expected) of
      (One, Many) -> True
      _ -> False

-- | Widen a precise tuple/tensor into its structural list view when possible.
--
-- This is the bridge that lets exact sequence types interact with explicit
-- `List` annotations and ambient declarations.
sequenceListView :: Type -> Maybe Type
sequenceListView ty =
  case tensorListView ty of
    Just listTy -> Just listTy
    Nothing -> tupleListView ty

-- | Recognize the plain built-in `List a` shape.
isPlainListType :: Type -> Bool
isPlainListType ty =
  case collectApps ty of
    (TCon "List", [_]) -> True
    _ -> False

-- | Decide whether a consistency-based escape hatch is allowed.
--
-- Gradual consistency exists to smooth interop with genuinely dynamic values,
-- not to silently blur two unrelated concrete types.
allowsGradualConsistency :: Type -> Type -> Bool
allowsGradualConsistency left right = hasDynamic left || hasDynamic right

-- | Check whether either side still contains unsolved metas.
hasUnresolvedMetas :: Type -> Type -> Bool
hasUnresolvedMetas left right = not (Set.null (freeMetas left <> freeMetas right))

-- | Detect whether a type tree mentions `dynamic` anywhere inside it.
hasDynamic :: Type -> Bool
hasDynamic = \case
  TDynamic -> True
  TTypeList items -> any hasDynamic items
  TFun _ left right -> hasDynamic left || hasDynamic right
  TRecord fields -> any hasDynamic fields
  TUnion members -> any hasDynamic members
  TApp fun arg -> hasDynamic fun || hasDynamic arg
  TForall _ body -> hasDynamic body
  TConditional actual patternTy yesTy noTy ->
    any hasDynamic [actual, patternTy, yesTy, noTy]
  _ -> False
