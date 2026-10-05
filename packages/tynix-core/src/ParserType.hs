{-# LANGUAGE OverloadedStrings #-}

-- | Parser for tynix type syntax.
--
-- The syntax combines Haskell-like binders (`forall`) with TypeScript-inspired
-- features (`extends`, `infer`) while keeping the visual shape light enough to
-- sit next to ordinary Nix code.
module ParserType (typeParser) where

import Data.Char (isUpper)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import ParserLexer
import Text.Megaparsec
import Type

-- | Entry point for type parsing.
typeParser :: Parser Type
typeParser = forallParser <|> (optional constraintContext *> conditionalParser)

-- | Parse explicit universal quantification.
forallParser :: Parser Type
forallParser = try $ do
  reserved "forall"
  vars <- some typeIdentifier
  _ <- symbol "."
  TForall vars <$> typeParser

-- | Parse a Haskell-style constraint context such as `Functor f =>` or
-- `(Eq a, Show a) =>`.
--
-- Constraints are accepted so signatures can document the capabilities they
-- rely on, but they are not enforced yet: tynix has no type classes, so the
-- context is dropped after parsing.
constraintContext :: Parser [Type]
constraintContext = try $ do
  constraints <- try (parens (sepBy1 appParser (symbol ","))) <|> (pure <$> appParser)
  _ <- symbol "=>"
  pure constraints

-- | Parse conditional types of the form `A extends B ? C : D`.
conditionalParser :: Parser Type
conditionalParser = do
  lhs <- functionParser
  option lhs $ do
    reserved "extends"
    rhs <- functionParser
    _ <- symbol "?"
    yesTy <- typeParser
    _ <- symbol ":"
    TConditional lhs rhs yesTy <$> typeParser

-- | Parse right-associative function arrows.
functionParser :: Parser Type
functionParser = do
  lhs <- unionParser
  option lhs $ do
    mult <- arrowMultiplicityParser
    TFun mult lhs <$> functionParser

arrowMultiplicityParser :: Parser Multiplicity
arrowMultiplicityParser =
  choice
    [ One <$ try (symbol "%1" *> symbol "->"),
      Many <$ symbol "->"
    ]

-- | Parse normalized unions.
unionParser :: Parser Type
unionParser = mkUnion <$> sepBy1 appParser (symbol "|")
  where
    mkUnion [oneTy] = oneTy
    mkUnion manyTypes = TUnion manyTypes

-- | Parse left-associated type applications.
appParser :: Parser Type
appParser = do
  head' <- atomParser
  rest <- many atomParser
  pure (foldl TApp head' rest)

-- | Parse atomic type forms.
atomParser :: Parser Type
atomParser =
  choice
    [ typeListParser,
      recordParser,
      TLit . LString <$> stringLiteral,
      TLit . LFloat <$> float,
      TLit . LInt <$> integer,
      TLit (LBool True) <$ reserved "true",
      TLit (LBool False) <$ reserved "false",
      TAny <$ reserved "any",
      TDynamic <$ reserved "dynamic",
      TUnknown <$ reserved "unknown",
      inferParser,
      parens typeParser,
      TCon "Tuple" <$ reserved "Tuple",
      varOrConParser
    ]

-- | Parse structural record types.
--
-- Fields are `name :: T;`, optional fields `name? :: T;`. A trailing `...`
-- (optionally named, `...r`) makes the record open: it may hold further
-- fields of unknown type.
recordParser :: Parser Type
recordParser = braces $ do
  fields <- many fieldParser
  rowTail <- optional (symbol "..." *> optional typeIdentifier <* optional (symbol ";"))
  pure $ case rowTail of
    Nothing -> TRecord (Map.fromList fields)
    Just Nothing -> TOpenRecord (Map.fromList fields) TDynamic
    Just (Just name) -> TOpenRecord (Map.fromList fields) (TVar name)
  where
    fieldParser = do
      name <- attrName
      isOptional <- option False (True <$ symbol "?")
      _ <- symbol "::"
      ty <- typeParser
      _ <- symbol ";"
      pure (name, if isOptional then TOptional ty else ty)

-- | Parse type-level shape lists such as `[2 3 4]`.
typeListParser :: Parser Type
typeListParser = TTypeList <$> brackets (many shapeItemParser)

shapeItemParser :: Parser Type
shapeItemParser =
  choice
    [ TLit . LString <$> stringLiteral,
      TLit . LFloat <$> float,
      TLit . LInt <$> integer,
      TLit (LBool True) <$ reserved "true",
      TLit (LBool False) <$ reserved "false",
      TAny <$ reserved "any",
      TDynamic <$ reserved "dynamic",
      TUnknown <$ reserved "unknown",
      inferParser,
      parens typeParser,
      TCon "Tuple" <$ reserved "Tuple",
      varOrConParser
    ]

-- | Parse an `infer` binder used inside conditional-type patterns.
inferParser :: Parser Type
inferParser = reserved "infer" *> (TInfer <$> typeIdentifier)

-- | Parse either a constructor-like name or a type variable.
--
-- Uppercase-leading identifiers are treated as constructors so users can write
-- aliases that feel familiar to both Haskell and TypeScript audiences.
varOrConParser :: Parser Type
varOrConParser = do
  name <- typeIdentifier
  pure $
    case name of
      _
        | Just (c, _) <- Text.uncons name,
          isUpper c ->
            TCon name
      _ -> TVar name
