("(" @open
  ")" @close)

("[" @open
  "]" @close)

("{" @open
  "}" @close)

(interpolation
  "${" @open
  "}" @close)

((string_expression
  "\"" @open
  "\"" @close)
  (#set! rainbow.exclude))

((indented_string_expression
  "''" @open
  "''" @close)
  (#set! rainbow.exclude))
