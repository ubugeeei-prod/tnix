; tynix locals (nvim-treesitter conventions).

[
  (let_expression)
  (let_attrset_expression)
  (rec_attrset_expression)
  (function_expression)
  (with_expression)
  (source_code)
] @local.scope

(let_expression
  (binding_set
    binding: (binding
      attrpath: (attrpath
        .
        attr: (identifier) @local.definition.var))))

(rec_attrset_expression
  (binding_set
    binding: (binding
      attrpath: (attrpath
        .
        attr: (identifier) @local.definition.var))))

(let_expression
  (binding_set
    binding: (inherit
      attrs: (inherited_attrs
        attr: (identifier) @local.definition.import))))

(function_expression
  universal: (identifier) @local.definition.parameter)

(formal
  name: (identifier) @local.definition.parameter)

(typed_parameter
  name: (identifier) @local.definition.parameter)

(type_alias
  name: (type_identifier) @local.definition.type)

(type_alias
  parameter: (type_variable) @local.definition.parameter)

(variable_expression
  name: (identifier) @local.reference)

(type_identifier) @local.reference
