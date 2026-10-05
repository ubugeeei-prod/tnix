(function_expression
  body: (_) @function.inside) @function.around

[
  (attrset_expression)
  (rec_attrset_expression)
  (record_type)
  (declaration_block)
] @class.around

(type_alias
  type: (_) @class.inside) @class.around

[
  (comment)
  (directive)
] @comment.around
