; Shell snippets in common derivation attributes (buildPhase, installPhase, ...).
(binding
  attrpath: (attrpath
    attr: (identifier) @_path)
  expression: (indented_string_expression
    (string_fragment) @injection.content)
  (#match? @_path "^([a-zA-Z]*Phase|preHook|postHook|shellHook|script|preStart|postStart|preStop|postStop|buildCommand|text)$")
  (#set! injection.language "bash")
  (#set! injection.combined))

; writeShellScript "name" ''...'' and friends.
(apply_expression
  function: (apply_expression
    function: [
      (variable_expression
        name: (identifier) @_func)
      (select_expression
        attrpath: (attrpath
          attr: (identifier) @_func .))
    ])
  argument: (indented_string_expression
    (string_fragment) @injection.content)
  (#match? @_func "^(writeShellScript|writeShellScriptBin|runCommand|runCommandLocal|runCommandCC)$")
  (#set! injection.language "bash")
  (#set! injection.combined))
