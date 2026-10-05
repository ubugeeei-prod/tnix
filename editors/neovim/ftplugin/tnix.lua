if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

vim.bo.commentstring = "# %s"
vim.bo.comments = "s1:/*,mb:*,ex:*/,:#"
vim.bo.shiftwidth = 2
vim.bo.softtabstop = 2
vim.bo.tabstop = 2
vim.bo.expandtab = true
-- Nix identifiers may contain `-` and `'` (e.g. `flake-utils`, `foldl'`).
vim.opt_local.iskeyword:append({ "-", "'" })
vim.bo.suffixesadd = ".tnix,.d.tnix,.nix"

vim.b.undo_ftplugin = table.concat({
  "setlocal commentstring< comments< shiftwidth< softtabstop< tabstop< expandtab< iskeyword< suffixesadd<",
  "unlet! b:did_ftplugin",
}, " | ")
