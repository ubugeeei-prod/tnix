-- Smoke-test the compiled tree-sitter-tynix parser together with the queries in
-- editors/neovim/queries/tynix.
--
-- Build the parser first, then run from the repository root:
--   cc -shared -fPIC -O2 -I editors/tree-sitter-tynix/src \
--     editors/tree-sitter-tynix/src/parser.c editors/tree-sitter-tynix/src/scanner.c -o "$TMPDIR/tynix.so"
--   TYNIX_PARSER="$TMPDIR/tynix.so" nvim --headless -u NONE -i NONE \
--     -c "lua vim.opt.runtimepath:append(vim.fn.getcwd() .. '/editors/neovim')" \
--     -l editors/neovim/test/treesitter_spec.lua
--
-- Requires Neovim 0.10+.

local parser_path = os.getenv("TYNIX_PARSER")
if not parser_path or parser_path == "" then
  print("tynix treesitter_spec: skipped (set TYNIX_PARSER to a compiled tynix parser)")
  return
end

local treesitter = require("tynix.treesitter")
local ok, err = treesitter.load_parser(parser_path)
assert(ok, "failed to load parser: " .. tostring(err))

for _, name in ipairs({ "highlights", "injections", "locals", "folds", "indents", "textobjects" }) do
  local files = vim.api.nvim_get_runtime_file("queries/tynix/" .. name .. ".scm", false)
  assert(#files > 0, "missing query file " .. name)
  local parsed, query_err = pcall(vim.treesitter.query.get, "tynix", name)
  assert(parsed and query_err, "query " .. name .. " failed to compile: " .. tostring(query_err))
end

local samples = vim.fn.globpath(vim.fn.getcwd(), "examples/**/*.tynix", false, true)
vim.list_extend(samples, vim.fn.globpath(vim.fn.getcwd(), "registry/**/*.tynix", false, true))
vim.list_extend(samples, { vim.fn.getcwd() .. "/editors/tree-sitter-tynix/examples/kitchen-sink.tynix" })
assert(#samples > 0, "no sample files found; run from the repository root")

local highlights = vim.treesitter.query.get("tynix", "highlights")
local captured = {}
for _, path in ipairs(samples) do
  local source = table.concat(vim.fn.readfile(path), "\n")
  local parser = vim.treesitter.get_string_parser(source, "tynix")
  local root = parser:parse()[1]:root()
  assert(not root:has_error(), "parse error in " .. path)
  for id in highlights:iter_captures(root, source) do
    captured[highlights.captures[id]] = true
  end
end

for _, expected in ipairs({ "keyword.type", "type", "type.definition", "string", "comment", "keyword.directive", "operator" }) do
  assert(captured[expected], "highlight capture @" .. expected .. " never matched the samples")
end

-- Start highlighting in a real buffer.
vim.cmd("edit " .. vim.fn.fnameescape(samples[#samples]))
vim.bo.filetype = "tynix"
assert(treesitter.start(0), "vim.treesitter.start failed for a tynix buffer")

print(string.format("tynix treesitter_spec: ok (%d files)", #samples))
