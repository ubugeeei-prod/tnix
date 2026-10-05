#!/bin/sh
# Compile the tree-sitter-tynix parser and smoke-test it with the Neovim queries.
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cc -shared -fPIC -O2 -I editors/tree-sitter-tynix/src \
  editors/tree-sitter-tynix/src/parser.c editors/tree-sitter-tynix/src/scanner.c \
  -o "$out/tynix.so"
TYNIX_PARSER="$out/tynix.so" nvim --headless -u NONE -i NONE \
  -c "lua vim.opt.runtimepath:append(vim.fn.getcwd() .. '/editors/neovim')" \
  -l editors/neovim/test/treesitter_spec.lua
