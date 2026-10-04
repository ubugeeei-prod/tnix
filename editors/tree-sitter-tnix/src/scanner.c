// External scanner for tree-sitter-tnix.
//
// Handles the context-sensitive pieces of the Nix lexical grammar that a
// regular-expression lexer cannot express cleanly:
//   * string fragments inside "..." and ''...'' (stopping before `${`,
//     escapes, and the closing delimiter, while keeping whitespace and `#`
//     as literal content);
//   * the start of a path literal (`./a`, `../a`, `/a`, `a/b`, `./${x}`),
//     which must be distinguished from `/`, `//`, and `/* comments */`;
//   * path fragments that immediately follow an interpolation inside a path.

#include "tree_sitter/parser.h"

#include <stdbool.h>
#include <wctype.h>

enum TokenType {
  STRING_FRAGMENT,
  INDENTED_STRING_FRAGMENT,
  PATH_START,
  PATH_FRAGMENT,
};

static void advance(TSLexer *lexer) { lexer->advance(lexer, false); }

static void skip(TSLexer *lexer) { lexer->advance(lexer, true); }

static bool is_path_char(int32_t c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-' ||
         c == '+';
}

static bool scan_string_fragment(TSLexer *lexer) {
  lexer->result_symbol = STRING_FRAGMENT;
  bool has_content = false;
  for (;;) {
    lexer->mark_end(lexer);
    switch (lexer->lookahead) {
    case '"':
    case '\\':
      return has_content;
    case '$':
      advance(lexer);
      if (lexer->lookahead == '{') {
        return has_content;
      }
      if (lexer->lookahead == '$') {
        // `$${` is a literal `${`; consume the second dollar so the brace is
        // treated as text as well.
        advance(lexer);
      }
      has_content = true;
      break;
    default:
      if (lexer->eof(lexer)) {
        return has_content;
      }
      advance(lexer);
      has_content = true;
      break;
    }
  }
}

static bool scan_indented_string_fragment(TSLexer *lexer) {
  lexer->result_symbol = INDENTED_STRING_FRAGMENT;
  bool has_content = false;
  for (;;) {
    lexer->mark_end(lexer);
    switch (lexer->lookahead) {
    case '$':
      advance(lexer);
      if (lexer->lookahead == '{') {
        return has_content;
      }
      if (lexer->lookahead == '$') {
        advance(lexer);
      }
      has_content = true;
      break;
    case '\'':
      advance(lexer);
      if (lexer->lookahead == '\'') {
        // Either the closing delimiter or an escape (`'''`, `''$`, `''\x`).
        return has_content;
      }
      has_content = true;
      break;
    default:
      if (lexer->eof(lexer)) {
        return has_content;
      }
      advance(lexer);
      has_content = true;
      break;
    }
  }
}

// Recognise the first chunk of a path literal. The token stops right before
// an interpolation (`${`) or at the end of the path.
static bool scan_path_start(TSLexer *lexer) {
  lexer->result_symbol = PATH_START;

  while (iswspace(lexer->lookahead)) {
    skip(lexer);
  }

  bool have_sep = false;
  bool have_after_sep = false;
  bool prev_slash = false;

  for (;;) {
    int32_t c = lexer->lookahead;
    if (c == '/') {
      if (prev_slash) {
        return false; // `//` is the update operator, never part of a path
      }
      have_sep = true;
      prev_slash = true;
      advance(lexer);
    } else if (is_path_char(c)) {
      if (have_sep) {
        have_after_sep = true;
      }
      prev_slash = false;
      advance(lexer);
    } else if (c == '$') {
      lexer->mark_end(lexer);
      advance(lexer);
      return lexer->lookahead == '{' && have_sep;
    } else {
      lexer->mark_end(lexer);
      return have_after_sep && !prev_slash;
    }
  }
}

static bool scan_path_fragment(TSLexer *lexer) {
  lexer->result_symbol = PATH_FRAGMENT;
  bool has_content = false;
  while (is_path_char(lexer->lookahead) || lexer->lookahead == '/') {
    advance(lexer);
    has_content = true;
  }
  lexer->mark_end(lexer);
  return has_content;
}

void *tree_sitter_tnix_external_scanner_create(void) { return NULL; }

void tree_sitter_tnix_external_scanner_destroy(void *payload) { (void)payload; }

unsigned tree_sitter_tnix_external_scanner_serialize(void *payload,
                                                     char *buffer) {
  (void)payload;
  (void)buffer;
  return 0;
}

void tree_sitter_tnix_external_scanner_deserialize(void *payload,
                                                   const char *buffer,
                                                   unsigned length) {
  (void)payload;
  (void)buffer;
  (void)length;
}

bool tree_sitter_tnix_external_scanner_scan(void *payload, TSLexer *lexer,
                                            const bool *valid_symbols) {
  (void)payload;

  // During error recovery every symbol is valid; let the internal lexer
  // resynchronise instead of greedily swallowing input as string content.
  if (valid_symbols[STRING_FRAGMENT] &&
      valid_symbols[INDENTED_STRING_FRAGMENT]) {
    return false;
  }

  if (valid_symbols[STRING_FRAGMENT]) {
    return scan_string_fragment(lexer);
  }

  if (valid_symbols[INDENTED_STRING_FRAGMENT]) {
    return scan_indented_string_fragment(lexer);
  }

  if (valid_symbols[PATH_FRAGMENT] &&
      (is_path_char(lexer->lookahead) || lexer->lookahead == '/')) {
    return scan_path_fragment(lexer);
  }

  if (valid_symbols[PATH_START]) {
    return scan_path_start(lexer);
  }

  return false;
}
