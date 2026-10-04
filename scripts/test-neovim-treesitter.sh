#!/bin/sh
# Compile the tree-sitter-tnix parser and smoke-test it with the Neovim queries.
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cc -shared -fPIC -O2 -I editors/tree-sitter-tnix/src \
  editors/tree-sitter-tnix/src/parser.c editors/tree-sitter-tnix/src/scanner.c \
  -o "$out/tnix.so"
TNIX_PARSER="$out/tnix.so" nvim --headless -u NONE -i NONE \
  -c "lua vim.opt.runtimepath:append(vim.fn.getcwd() .. '/editors/neovim')" \
  -l editors/neovim/test/treesitter_spec.lua
