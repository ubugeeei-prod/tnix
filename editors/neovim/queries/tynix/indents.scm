; Generated from editors/tree-sitter-tynix/queries by scripts/sync-queries.mjs. Do not edit.
[
  (attrset_expression)
  (rec_attrset_expression)
  (let_attrset_expression)
  (list_expression)
  (parenthesized_expression)
  (formals)
  (record_type)
  (declaration_block)
  (let_expression)
  (if_expression)
] @indent.begin

(let_expression
  "in" @indent.branch)

(if_expression
  [
    "then"
    "else"
  ] @indent.branch)

[
  "}"
  "]"
  ")"
] @indent.branch @indent.end

(indented_string_expression) @indent.ignore

(comment) @indent.auto
