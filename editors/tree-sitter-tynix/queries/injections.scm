; tynix injections (nvim-treesitter conventions).

((comment) @injection.content
  (#set! injection.language "comment"))

; /* lang */ ''...'' or /* lang */ "..." annotates the language of the string.
((comment) @injection.language
  .
  [
    (indented_string_expression
      (string_fragment) @injection.content)
    (string_expression
      (string_fragment) @injection.content)
  ]
  (#gsub! @injection.language "/%*%s*([%w%p]+)%s*%*/" "%1")
  (#set! injection.combined))

; Shell snippets in common derivation attributes (buildPhase, installPhase, ...).
(binding
  attrpath: (attrpath
    attr: (identifier) @_path)
  expression: (indented_string_expression
    (string_fragment) @injection.content)
  (#lua-match? @_path "^%a*Phase$")
  (#set! injection.language "bash")
  (#set! injection.combined))

(binding
  attrpath: (attrpath
    attr: (identifier) @_path)
  expression: (indented_string_expression
    (string_fragment) @injection.content)
  (#any-of? @_path
    "preHook" "postHook" "shellHook" "script" "preStart" "postStart" "preStop" "postStop"
    "buildCommand" "text")
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
  (#any-of? @_func
    "writeShellScript" "writeShellScriptBin" "runCommand" "runCommandLocal" "runCommandCC")
  (#set! injection.language "bash")
  (#set! injection.combined))
