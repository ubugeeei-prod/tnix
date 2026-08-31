{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Pretty-printers for emitted `.nix`, `.d.tnix`, and human-facing type text.
--
-- One module owns all rendering so that CLI output, declaration files, and
-- debug/test expectations share the same surface representation.
module Pretty
  ( renderDeclarationFile,
    renderExpr,
    renderKind,
    renderProgram,
    renderProgramAsNix,
    renderScheme,
    renderType,
  )
where

import Data.Char (isAlphaNum, isLetter)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Indexed (tensorView, tupleView)
import Numeric (showGFloat)
import Prettyprinter
import Prettyprinter.Render.Text qualified as Render
import Syntax
import Type

-- | Render a full program back to tnix surface syntax, preserving type aliases,
-- ambient declarations, and embedded type annotations (unlike
-- 'renderProgramAsNix', which erases type-only syntax). Used by the LSP
-- formatter. Declarations are emitted before the root expression; comments are
-- not represented in the AST, so callers must guard against destroying them.
renderProgram :: Program -> Text
renderProgram program =
  render $
    vsep $
      map prettyAlias (programAliases program)
        <> map prettyAmbient (programAmbient program)
        <> maybe [] (\marked -> [prettyExpr 0 (markedValue marked)]) (programExpr program)

prettyAmbient :: AmbientDecl -> Doc ann
prettyAmbient decl =
  prettyDecl
    (ambientPath decl)
    [(ambientEntryName entry, ambientEntryType entry) | entry <- ambientEntries decl]

-- | Render an executable program back to plain Nix code.
renderProgramAsNix :: Program -> Either Text Text
renderProgramAsNix program =
  maybe (Left "declaration-only files cannot be compiled to .nix") (Right . render . prettyExpr 0 . markedValue) (programExpr program)

-- | Render a declaration file for a target path and exported entries.
renderDeclarationFile :: FilePath -> [TypeAlias] -> [(Name, Type)] -> Text
renderDeclarationFile path aliases entries = render $ vsep (map prettyAlias aliases <> [prettyDecl path entries])

-- | Render an expression using tnix/Nix surface syntax.
renderExpr :: Expr -> Text
renderExpr = render . prettyExpr 0

-- | Render a type without scheme quantifiers.
renderType :: Type -> Text
renderType = render . prettyType 0

-- | Render a kind using arrow syntax for higher-kinded constructors.
renderKind :: Kind -> Text
renderKind = render . prettyKind 0

-- | Render a polymorphic scheme for CLI and LSP display.
renderScheme :: Scheme -> Text
renderScheme (Scheme vars ty) =
  render $
    if null vars
      then prettyType 0 ty
      else "forall" <+> hsep (pretty <$> vars) <> "." <+> prettyType 0 ty

render :: Doc ann -> Text
render = Render.renderStrict . layoutPretty defaultLayoutOptions

prettyAlias :: TypeAlias -> Doc ann
prettyAlias alias =
  "type"
    <+> pretty (typeAliasName alias)
    <+> hsep (pretty <$> typeAliasParams alias)
    <+> "="
    <+> prettyType 0 (typeAliasBody alias)
    <> ";"

prettyDecl :: FilePath -> [(Name, Type)] -> Doc ann
prettyDecl path entries =
  vsep
    [ "declare" <+> prettyQuoted (Text.pack path) <+> "{",
      indent 2 (vsep [prettyAttrName name <+> "::" <+> prettyType 0 ty <> ";" | (name, ty) <- entries]),
      "};"
    ]

prettyExpr :: Int -> Expr -> Doc ann
prettyExpr p = \case
  EVar name -> pretty name
  EString value -> prettyStringLiteral value
  EFloat value -> pretty (prettyFloat value)
  EInt value -> pretty value
  EBool True -> "true"
  EBool False -> "false"
  ENull -> "null"
  EPath path -> pretty path
  -- Control-flow forms extend to the right, so they must be parenthesized
  -- whenever they appear in any tighter position (p > 0).
  ELambda pattern' body -> parenIf (p > 0) (prettyPattern pattern' <> ":" <+> prettyExpr 0 body)
  EIf a b c -> parenIf (p > 0) (vsep ["if" <+> prettyExpr 0 a, "then" <+> prettyExpr 0 b, "else" <+> prettyExpr 0 c])
  ELet items body -> parenIf (p > 0) (vsep ["let", indent 2 (vsep (map (prettyLet . markedValue) items)), "in" <+> prettyExpr 0 body])
  EAssert cond body -> parenIf (p > 0) ("assert" <+> prettyExpr 0 cond <> ";" <+> prettyExpr 0 body)
  EWith scope body -> parenIf (p > 0) ("with" <+> prettyExpr 0 scope <> ";" <+> prettyExpr 0 body)
  -- Operators: each level parenthesizes only when the surrounding context binds
  -- tighter than the operator, and the non-associative operand side is bumped by
  -- one so equal-precedence nesting parenthesizes correctly.
  EBinaryOp op left right ->
    let q = binOpPrec op
        (leftP, rightP) =
          if binOpRightAssoc op
            then (q + 1, q)
            else (q, q + 1)
     in parenIf (p > q) (prettyExpr leftP left <+> pretty (binOpSymbol op) <+> prettyExpr rightP right)
  EUnaryOp OpNot operand -> parenIf (p > 6) ("!" <> prettyExpr 6 operand)
  EHasAttr base path -> parenIf (p > 10) (prettyExpr 11 base <+> "?" <+> hcat (punctuate "." (map prettyAttrName path)))
  ECast expr ty -> parenIf (p > 11) (prettyExpr 11 expr <+> "as" <+> prettyType 0 ty)
  EApp f x -> parenIf (p > 12) (prettyExpr 12 f <+> prettyExpr 13 x)
  ESelect base steps -> parenIf (p > 13) (prettyExpr 13 base <> foldMap prettySelectStep steps)
  -- Self-delimiting atoms never need outer parentheses; list/application
  -- operands are rendered tightly so nested calls and operators stay grouped.
  EAttrSet items -> vsep ["{", indent 2 (vsep (map prettyAttr items)), "}"]
  ERec items -> vsep ["rec {", indent 2 (vsep (map prettyAttr items)), "}"]
  EList items -> "[" <+> hsep (map (prettyExpr 13) items) <+> "]"
  EInterp form parts -> prettyInterp form parts

prettyLet :: LetItem -> Doc ann
prettyLet = \case
  LetSignature name ty -> pretty name <+> "::" <+> prettyType 0 ty <> ";"
  LetBinding name expr -> pretty name <+> "=" <+> prettyExpr 0 expr <> ";"

prettyPattern :: Pattern -> Doc ann
prettyPattern = \case
  PVar name _ -> pretty name
  PAttrSet names open ->
    case map pretty names <> [ellipsis | open] of
      [] -> "{}"
      items -> "{ " <> hsep (punctuate "," items) <> " }"
    where
      ellipsis = "..."

prettySelectStep :: SelectStep -> Doc ann
prettySelectStep = \case
  SelectName name -> "." <> prettyAttrName name
  SelectDynamic expr -> ".${" <> prettyExpr 0 expr <> "}"

prettyAttr :: AttrItem -> Doc ann
prettyAttr = \case
  AttrField name expr -> prettyAttrName name <+> "=" <+> prettyExpr 0 expr <> ";"
  AttrInherit names -> "inherit" <+> hsep (pretty <$> names) <> ";"

prettyAttrName :: Name -> Doc ann
prettyAttrName name
  | isBareAttrName name && name /= "inherit" = pretty name
  | otherwise = prettyQuoted name

prettyStringLiteral :: StringLiteral -> Doc ann
prettyStringLiteral = \case
  DoubleQuoted value -> prettyQuoted value
  Indented value -> "''" <> verbatim (escapeIndented True True value) <> "''"

-- | Render an interpolated string back to its surface form, restoring `${...}`
-- antiquotations around the embedded expressions.
prettyInterp :: InterpForm -> [StringPart] -> Doc ann
prettyInterp form parts =
  let lastIndex = length parts - 1
      body = hcat [prettyStringPart form (index == 0) (index == lastIndex) part | (index, part) <- zip [0 ..] parts]
   in case form of
        InterpDouble -> dquotes body
        InterpIndented -> "''" <> body <> "''"

-- | Render one segment of an interpolated string.
--
-- The two flags say whether the segment touches the opening or the closing
-- delimiter, which is what decides whether a boundary @\'@ inside an indented
-- run has to be escaped.
prettyStringPart :: InterpForm -> Bool -> Bool -> StringPart -> Doc ann
prettyStringPart form atStart atEnd = \case
  StrText text ->
    case form of
      InterpDouble -> pretty (escapeDoubleQuoted text)
      InterpIndented -> verbatim (escapeIndented atStart atEnd text)
  StrExpr expr -> "${" <> prettyExpr 0 expr <> "}"

prettyType :: Int -> Type -> Doc ann
prettyType p ty =
  case tupleView ty of
    Just items -> parenIf (p > 2) ("Tuple" <+> prettyType 3 (TTypeList items))
    Nothing ->
      case tensorView ty of
        Just (dims, elemTy) ->
          case dims of
            [lenTy] -> parenIf (p > 2) ("Vec" <+> prettyType 3 lenTy <+> prettyType 3 elemTy)
            [rowsTy, colsTy] -> parenIf (p > 2) ("Matrix" <+> prettyType 3 rowsTy <+> prettyType 3 colsTy <+> prettyType 3 elemTy)
            _ -> parenIf (p > 2) ("Tensor" <+> prettyType 3 (TTypeList dims) <+> prettyType 3 elemTy)
        Nothing ->
          case ty of
            TVar name -> pretty name
            TCon name -> pretty name
            TMeta n -> pretty ("?" <> show n)
            TLit (LString text) -> prettyQuoted text
            TLit (LFloat n) -> pretty (prettyFloat n)
            TLit (LInt n) -> pretty n
            TLit (LBool True) -> "true"
            TLit (LBool False) -> "false"
            TAny -> "any"
            TTypeList items -> "[" <+> hsep (prettyType 3 <$> items) <+> "]"
            TDynamic -> "dynamic"
            TUnknown -> "unknown"
            TFun mult a b ->
              let arrow =
                    case mult of
                      One -> "%1 ->"
                      Many -> "->"
               in parenIf (p > 0) (prettyType 1 a <+> arrow <+> prettyType 0 b)
            TRecord fields -> vsep ["{", indent 2 (vsep [prettyAttrName k <+> "::" <+> prettyType 0 v <> ";" | (k, v) <- Map.toList fields]), "}"]
            TUnion members -> parenIf (p > 1) (hsep (punctuate " |" (map (prettyType 2) members)))
            TApp f x -> parenIf (p > 2) (prettyType 2 f <+> prettyType 3 x)
            TForall vars body -> parenIf (p > 0) ("forall" <+> hsep (pretty <$> vars) <> "." <+> prettyType 0 body)
            TConditional a b c d -> parenIf (p > 0) (prettyType 2 a <+> "extends" <+> prettyType 2 b <+> "?" <+> prettyType 0 c <+> ":" <+> prettyType 0 d)
            TInfer name -> "infer" <+> pretty name

-- | Emit text with its own line breaks, immune to the surrounding layout.
--
-- An indented string keeps its body verbatim, so the renderer must not add the
-- enclosing block's indentation after each newline: doing so changes the string
-- and compounds every time the file is compiled again. Resetting the nesting
-- level to zero for the body keeps rendering idempotent.
verbatim :: Text -> Doc ann
verbatim text = nesting (\level -> nest (negate level) (pretty text))

-- | Render text as a Nix double-quoted string literal, escaping every
-- character that would otherwise change how the result re-parses.
prettyQuoted :: Text -> Doc ann
prettyQuoted = dquotes . pretty . escapeDoubleQuoted

-- | Escape text for a Nix double-quoted string literal.
--
-- Quotes, backslashes, and the control characters Nix spells with an escape
-- are rewritten to their escaped forms. A @$@ is escaped only when it would
-- otherwise open an antiquotation, so ordinary shell-ish text stays readable.
escapeDoubleQuoted :: Text -> Text
escapeDoubleQuoted = Text.pack . go . Text.unpack
  where
    go [] = []
    go ('"' : rest) = '\\' : '"' : go rest
    go ('\\' : rest) = '\\' : '\\' : go rest
    go ('\n' : rest) = '\\' : 'n' : go rest
    go ('\r' : rest) = '\\' : 'r' : go rest
    go ('\t' : rest) = '\\' : 't' : go rest
    go ('$' : '{' : rest) = '\\' : '$' : '{' : go rest
    go (char : rest) = char : go rest

-- | Escape text for a Nix indented (@\'\'@) string literal.
--
-- Antiquotation openers become @\'\'${@. A single quote only needs escaping
-- when it would pair up with a neighbouring quote and be read back as
-- something else: at the opening delimiter, at the closing delimiter, before
-- another quote, or immediately before an escaped @${@. Everywhere else a
-- bare quote round-trips as itself, which keeps embedded shell snippets
-- legible.
--
-- @atStart@ and @atEnd@ say whether this run of text touches the opening or
-- the closing delimiter; interpolated strings pass 'False' for the segments
-- that sit next to an antiquotation instead.
escapeIndented :: Bool -> Bool -> Text -> Text
escapeIndented atStart atEnd = Text.pack . go atStart . Text.unpack
  where
    go _ [] = []
    go _ ('$' : '{' : rest) = '\'' : '\'' : '$' : '{' : go False rest
    go atBoundary ('\'' : rest)
      | needsEscape atBoundary rest = '\'' : '\'' : '\\' : '\'' : go False rest
      | otherwise = '\'' : go False rest
    go _ (char : rest) = char : go False rest

    needsEscape atBoundary rest =
      atBoundary
        || (atEnd && null rest)
        || take 1 rest == "'"
        || take 2 rest == "${"

isBareAttrName :: Text -> Bool
isBareAttrName name =
  case Text.uncons name of
    Just (first, rest) -> attrNameStart first && Text.all attrNameCont rest
    Nothing -> False
  where
    attrNameStart c = isLetter c || c == '_'
    attrNameCont c = isAlphaNum c || c `elem` ("_'-" :: String)

prettyKind :: Int -> Kind -> Doc ann
prettyKind p = \case
  KType -> "Type"
  KMeta n -> pretty ("?" <> show n)
  KFun a b -> parenIf (p > 0) (prettyKind 1 a <+> "->" <+> prettyKind 0 b)

parenIf :: Bool -> Doc ann -> Doc ann
parenIf True = parens
parenIf False = id

-- | Binding tightness of each binary operator (higher binds tighter), matching
-- the parser's precedence ladder so re-parsing reproduces the same tree.
binOpPrec :: BinOp -> Int
binOpPrec = \case
  OpOr -> 1
  OpAnd -> 2
  OpEq -> 3
  OpNeq -> 3
  OpLt -> 4
  OpGt -> 4
  OpLe -> 4
  OpGe -> 4
  OpUpdate -> 5
  OpAdd -> 7
  OpSub -> 7
  OpMul -> 8
  OpConcat -> 9

-- | List concatenation and attribute-set update are right-associative.
binOpRightAssoc :: BinOp -> Bool
binOpRightAssoc = \case
  OpUpdate -> True
  OpConcat -> True
  _ -> False

binOpSymbol :: BinOp -> Text
binOpSymbol = \case
  OpAdd -> "+"
  OpSub -> "-"
  OpMul -> "*"
  OpConcat -> "++"
  OpUpdate -> "//"
  OpEq -> "=="
  OpNeq -> "!="
  OpLt -> "<"
  OpGt -> ">"
  OpLe -> "<="
  OpGe -> ">="
  OpAnd -> "&&"
  OpOr -> "||"

prettyFloat :: Double -> String
prettyFloat n =
  let rendered = showGFloat Nothing n ""
   in if any (`elem` (".eE" :: String)) rendered
        then rendered
        else rendered <> ".0"
