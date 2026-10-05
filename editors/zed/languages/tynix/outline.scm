(type_alias
  "type" @context
  name: (_) @name) @item

(ambient_declaration
  "declare" @context
  path: (_) @name) @item

(declaration_block
  entry: (type_signature
    name: (_) @name
    "::" @context) @item)

(binding_set
  binding: (binding
    attrpath: (_) @name) @item)

(binding_set
  binding: (inherit
    "inherit" @context
    attrs: (_) @name) @item)

(binding_set
  binding: (inherit_from
    "inherit" @context
    attrs: (_) @name) @item)
