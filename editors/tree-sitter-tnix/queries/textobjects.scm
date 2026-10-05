; nvim-treesitter-textobjects captures.

(function_expression
  body: (_) @function.inner) @function.outer

(function_expression
  universal: (identifier) @parameter.inner)

(formal) @parameter.inner

(typed_parameter) @parameter.outer

(apply_expression
  argument: (_) @call.inner) @call.outer

(comment) @comment.outer

(directive) @comment.outer

(binding
  expression: (_) @assignment.rhs) @assignment.outer

(binding
  attrpath: (_) @assignment.lhs)

(type_signature
  type: (_) @assignment.rhs) @assignment.outer

[
  (attrset_expression)
  (rec_attrset_expression)
  (record_type)
  (declaration_block)
] @class.outer

(if_expression) @conditional.outer

(if_expression
  consequence: (_) @conditional.inner)

(if_expression
  alternative: (_) @conditional.inner)
