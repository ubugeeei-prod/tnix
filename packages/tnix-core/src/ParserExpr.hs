{-# LANGUAGE OverloadedStrings #-}

-- | Parser for top-level declarations and executable expressions.
--
-- The parser preserves Nix-like surface structure as much as possible so that
-- compilation can be implemented as a mostly mechanical erasure pass.
module ParserExpr (expressionParser, programParser) where

import Data.Either (lefts, rights)
import Data.Functor (($>))
import Data.Text qualified as Text
import ParserLexer
import ParserType
import Syntax
import Text.Megaparsec
import Text.Megaparsec.Char (char, string)
import Text.Megaparsec.Char.Lexer qualified as L
import Type

-- | Parse a full tnix source file.
programParser :: Parser Program
programParser = do
  decls <- many declarationParser
  expr <- optional (markCurrent expressionParser)
  pure
    Program
      { programAliases = lefts decls,
        programAmbient = rights decls,
        programExpr = expr
      }

-- | Parse either a type alias or an ambient declaration.
declarationParser :: Parser (Either TypeAlias AmbientDecl)
declarationParser = try (Left <$> aliasParser) <|> (Right <$> ambientParser)

-- | Parse a top-level `type` alias declaration.
aliasParser :: Parser TypeAlias
aliasParser = do
  reserved "type"
  name <- identifier
  params <- many identifier
  _ <- symbol "="
  body <- typeParser
  _ <- symbol ";"
  pure TypeAlias{typeAliasName = name, typeAliasParams = params, typeAliasBody = body}

-- | Parse a `declare` block that describes an existing `.nix` module.
ambientParser :: Parser AmbientDecl
ambientParser = do
  reserved "declare"
  path <- pathLiteral <|> (Text.unpack <$> stringLiteral)
  entries <- braces (many ambientEntry)
  _ <- symbol ";"
  pure AmbientDecl{ambientPath = path, ambientEntries = entries}

-- | Parse a single ambiently-exported member.
ambientEntry :: Parser AmbientEntry
ambientEntry = do
  name <- attrName
  _ <- symbol "::"
  ty <- typeParser
  _ <- symbol ";"
  pure AmbientEntry{ambientEntryName = name, ambientEntryType = ty}

-- | Parse any expression form supported by the prototype.
expressionParser :: Parser Expr
expressionParser = choice [ifParser, letParser, assertParser, withParser, try lambdaParser, orParser]

-- | Parse a Nix-style conditional expression.
ifParser :: Parser Expr
ifParser = do
  reserved "if"
  cond <- expressionParser
  reserved "then"
  yesExpr <- expressionParser
  reserved "else"
  EIf cond yesExpr <$> expressionParser

-- | Parse a Nix-style `assert condition; body` expression.
assertParser :: Parser Expr
assertParser = do
  reserved "assert"
  cond <- expressionParser
  _ <- symbol ";"
  EAssert cond <$> expressionParser

-- | Parse a Nix-style `with scope; body` expression.
withParser :: Parser Expr
withParser = do
  reserved "with"
  scope <- expressionParser
  _ <- symbol ";"
  EWith scope <$> expressionParser

-- | Parse a `let ... in ...` block with optional type signatures.
letParser :: Parser Expr
letParser = do
  reserved "let"
  items <- many (markCurrent letItemParser)
  reserved "in"
  ELet items <$> expressionParser

-- | Parse either a type signature or a value binding inside a `let`.
--
-- Both forms open with the same identifier, so it is parsed once and the two
-- tails are tried after it. Committing to the shared prefix keeps `many
-- letItemParser` from re-lexing every binding name, and still stops cleanly at
-- `in`, where `identifier` fails without consuming.
letItemParser :: Parser LetItem
letItemParser = do
  name <- identifier
  signatureFor name <|> bindingFor name
  where
    signatureFor name = do
      _ <- symbol "::"
      ty <- typeParser
      _ <- symbol ";"
      pure (LetSignature name ty)
    bindingFor name = do
      _ <- symbol "="
      expr <- expressionParser
      _ <- symbol ";"
      pure (LetBinding name expr)

-- | Parse a lambda using tnix's Haskell-like binder syntax.
lambdaParser :: Parser Expr
lambdaParser = do
  pattern' <- patternParser
  _ <- symbol ":"
  ELambda pattern' <$> expressionParser

-- | Parse TypeScript-style `expr as Type` chains.
--
-- Casts bind looser than application and field selection, so `f x as Int`
-- means `(f x) as Int`, while casting larger control-flow expressions still
-- requires parentheses.
castParser :: Parser Expr
castParser = do
  base <- applicationParser
  casts <- many (reserved "as" *> typeParser)
  pure (foldl ECast base casts)

-- | Operator precedence ladder, from loosest to tightest binding.
--
-- The layering mirrors Nix: boolean `||` binds loosest, then `&&`, equality,
-- ordered comparisons, prefix `!`, and finally numeric `+`. Each level sits
-- above application/selection and explicit casts so expressions such as
-- `f x + 1 < limit && ok` keep the expected Nix shape.
orParser :: Parser Expr
orParser = chainLeft1 andParser (EBinaryOp OpOr <$ symbol "||")

andParser :: Parser Expr
andParser = chainLeft1 equalityParser (EBinaryOp OpAnd <$ symbol "&&")

equalityParser :: Parser Expr
equalityParser =
  chainLeft1
    relationalParser
    ((EBinaryOp OpEq <$ symbol "==") <|> (EBinaryOp OpNeq <$ symbol "!="))

relationalParser :: Parser Expr
relationalParser =
  chainLeft1
    updateParser
    ( choice
        [ EBinaryOp OpLe <$ symbol "<=",
          EBinaryOp OpGe <$ symbol ">=",
          EBinaryOp OpLt <$ symbol "<",
          EBinaryOp OpGt <$ symbol ">"
        ]
    )

-- | Parse right-associated attribute-set update (`//`), binding tighter than
-- comparisons but looser than prefix `!`, matching Nix.
updateParser :: Parser Expr
updateParser = chainRight1 notParser (EBinaryOp OpUpdate <$ symbol "//")

-- | Parse prefix boolean negation, falling through to numeric addition.
notParser :: Parser Expr
notParser = (EUnaryOp OpNot <$> (symbol "!" *> notParser)) <|> additionParser

-- | Parse left-associated additive arithmetic (`+`, `-`).
additionParser :: Parser Expr
additionParser =
  chainLeft1
    multiplicationParser
    ((EBinaryOp OpAdd <$ symbol "+") <|> (EBinaryOp OpSub <$ symbol "-"))

-- | Parse left-associated multiplicative arithmetic (`*`), binding tighter
-- than additive operators.
multiplicationParser :: Parser Expr
multiplicationParser = chainLeft1 concatParser (EBinaryOp OpMul <$ symbol "*")

-- | Parse right-associated list concatenation (`++`), binding tighter than
-- arithmetic so `xs ++ ys ++ zs` groups as `xs ++ (ys ++ zs)`.
concatParser :: Parser Expr
concatParser = chainRight1 hasAttrParser (EBinaryOp OpConcat <$ symbol "++")

-- | Parse the attribute-presence test (`e ? attrpath`), binding tighter than
-- concatenation. The right-hand side is a dotted attribute path, not an
-- arbitrary expression, matching Nix.
hasAttrParser :: Parser Expr
hasAttrParser = do
  base <- castParser
  option base (EHasAttr base <$> (symbol "?" *> attrPathParser))
  where
    attrPathParser = sepBy1 attrName (symbol ".")

-- | Parse left-associated application chains.
applicationParser :: Parser Expr
applicationParser = do
  head' <- postfixParser
  rest <- many postfixParser
  pure (foldl EApp head' rest)

-- | Parse postfix field selections without stealing path literals.
postfixParser :: Parser Expr
postfixParser = do
  base <- atomParser
  steps <- many (try selectStepParser)
  pure $ if null steps then base else ESelect base steps

selectStepParser :: Parser SelectStep
selectStepParser = do
  _ <- symbol "."
  try dynamicStepParser <|> (SelectName <$> attrName)
  where
    dynamicStepParser = do
      _ <- symbol "${"
      stepExpr <- expressionParser
      _ <- symbol "}"
      pure (SelectDynamic stepExpr)

-- | Parse atomic expression forms.
atomParser :: Parser Expr
atomParser =
  choice
    [ parens expressionParser,
      recAttrSetParser,
      attrSetParser,
      listParser,
      stringExpr,
      EFloat <$> float,
      EInt <$> integer,
      EBool True <$ reserved "true",
      EBool False <$ reserved "false",
      ENull <$ reserved "null",
      EPath <$> pathLiteral,
      EVar "import" <$ reserved "import",
      EVar <$> identifier
    ]

-- | Parse an attribute set.
attrSetParser :: Parser Expr
attrSetParser = EAttrSet <$> braces (many attrParser)

-- | Parse a recursive attribute set (`rec { ... }`).
recAttrSetParser :: Parser Expr
recAttrSetParser = reserved "rec" *> (ERec <$> braces (many attrParser))

-- | Parse a string literal, producing an interpolated string when it contains
-- `${...}` antiquotations and a plain 'EString' otherwise. Both double-quoted
-- and indented `'' ... ''` forms are supported.
stringExpr :: Parser Expr
stringExpr = lexeme (doubleQuotedExpr <|> indentedExpr)

doubleQuotedExpr :: Parser Expr
doubleQuotedExpr =
  mkStringExpr InterpDouble
    <$> (char '"' *> many (interpPart <|> doubleTextPart) <* char '"')

indentedExpr :: Parser Expr
indentedExpr =
  mkStringExpr InterpIndented
    <$> (string "''" *> many (interpPart <|> indentedTextPart) <* string "''")

-- | An antiquoted `${ expr }` segment shared by both string forms. The leading
-- `${` is wrapped in 'try' so a literal `$` not followed by `{` falls through to
-- the surrounding text parser.
interpPart :: Parser StringPart
interpPart = StrExpr <$> (try (string "${") *> sc *> expressionParser <* char '}')

doubleTextPart :: Parser StringPart
doubleTextPart = StrText . Text.pack <$> some doubleTextChar

-- | A literal character inside a double-quoted string. `\$` escapes a literal
-- dollar; otherwise standard escapes are honored and `${`/`"` terminate the run.
doubleTextChar :: Parser Char
doubleTextChar =
  (try (char '\\' *> char '$') $> '$')
    <|> (notFollowedBy (string "${") *> notFollowedBy (char '"') *> L.charLiteral)

indentedTextPart :: Parser StringPart
indentedTextPart = StrText . Text.concat <$> some indentedChunk

-- | A literal chunk inside an indented string.
--
-- The escapes mirror Nix: `''${` and `''$` produce a literal dollar, `'''`
-- produces a literal `''`, and `''\\` takes the following character literally
-- (with the usual `n`/`r`/`t` spellings). Every other character is preserved
-- verbatim.
indentedChunk :: Parser Text.Text
indentedChunk =
  (try (string "''${") $> "${")
    <|> (try (string "''$") $> "$")
    <|> (try (string "'''") $> "''")
    <|> (Text.singleton <$> (try (string "''\\") *> indentedEscapeChar))
    <|> (Text.singleton <$> (notFollowedBy (string "${") *> notFollowedBy (string "''") *> anySingle))

-- | Decode the character following an `''\\` escape inside an indented string.
indentedEscapeChar :: Parser Char
indentedEscapeChar = decode <$> anySingle
  where
    decode 'n' = '\n'
    decode 'r' = '\r'
    decode 't' = '\t'
    decode other = other

-- | Collapse parsed segments into a plain 'EString' when there is no
-- interpolation; otherwise keep the interpolated representation.
mkStringExpr :: InterpForm -> [StringPart] -> Expr
mkStringExpr form parts
  | all isText parts = EString (literalFor form (Text.concat [t | StrText t <- parts]))
  | otherwise = EInterp form parts
  where
    isText StrText{} = True
    isText StrExpr{} = False
    literalFor InterpDouble = DoubleQuoted
    literalFor InterpIndented = Indented

-- | Parse either an explicit field or an `inherit` clause.
attrParser :: Parser AttrItem
attrParser = try inheritParser <|> fieldParser
  where
    inheritParser = reserved "inherit" *> (AttrInherit <$> some identifier) <* symbol ";"
    fieldParser = do
      name <- attrName
      _ <- symbol "="
      expr <- expressionParser
      _ <- symbol ";"
      pure (AttrField name expr)

-- | Parse a list literal.
listParser :: Parser Expr
listParser = EList <$> brackets (many listItem)
  where
    listItem = choice [ifParser, letParser, try lambdaParser, listAdditionParser]
    listAdditionParser = chainLeft1 listCastParser (EBinaryOp OpAdd <$ symbol "+")
    listCastParser = do
      base <- postfixParser
      casts <- many (reserved "as" *> typeParser)
      pure (foldl ECast base casts)

-- | Parse a lambda binder pattern with an optional inline annotation.
patternParser :: Parser Pattern
patternParser = try (parens typed) <|> try attrSetPattern <|> (PVar <$> identifier <*> pure Nothing)
  where
    typed = do
      name <- identifier
      _ <- symbol "::"
      PVar name . Just <$> typeParser
    attrSetPattern = braces $ do
      items <- sepEndBy patternItem (symbol ",")
      let names = lefts items
          open = any isEllipsis items
      pure (PAttrSet names open)
    patternItem = (Left <$> identifier) <|> (Right () <$ symbol "...")
    isEllipsis item =
      case item of
        Right () -> True
        Left _ -> False

markCurrent :: Parser a -> Parser (Marked a)
markCurrent parser = Marked <$> directiveForCurrentLine <*> parser

chainLeft1 :: Parser a -> Parser (a -> a -> a) -> Parser a
chainLeft1 item op = do
  first <- item
  rest first
  where
    rest acc =
      ( do
          f <- op
          next <- item
          rest (f acc next)
      )
        <|> pure acc

chainRight1 :: Parser a -> Parser (a -> a -> a) -> Parser a
chainRight1 item op = do
  first <- item
  ( do
      f <- op
      rest <- chainRight1 item op
      pure (f first rest)
    )
    <|> pure first
