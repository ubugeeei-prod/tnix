// TextMate grammar for `.tnix` / `.d.tnix` code fences on the docs site.
//
// Editors get precise highlighting from the language server's semantic
// tokens; this grammar only needs to be good enough for static docs. It knows
// the Nix expression surface plus the type-only layer tnix adds (`::`
// annotations, `type`, `declare`, `forall`, `extends`/`infer`, `as`, and the
// `# @tnix-*` directives) so that the brand code theme can paint every
// type-only construct in the "annotation" colour. Those are exactly the
// tokens that disappear when tnix compiles to `.nix`.

const typeExpression = {
  patterns: [
    { include: "#comment" },
    { include: "#typeRecord" },
    { begin: "\\(", end: "\\)", patterns: [{ include: "#typeExpr" }] },
    { include: "#string" },
    { match: "\\b(forall|extends|infer)\\b", name: "keyword.other.type.tnix" },
    { match: "\\b(dynamic|unknown|any)\\b", name: "support.type.gradual.tnix" },
    { match: "\\b(true|false)\\b", name: "constant.language.boolean.tnix" },
    { match: "-?\\b\\d+(\\.\\d+)?\\b", name: "constant.numeric.tnix" },
    { match: "\\b[A-Z][A-Za-z0-9_'-]*", name: "entity.name.type.tnix" },
    { match: "%1\\s*->|->|\\||\\?|:(?!:)", name: "keyword.operator.type.tnix" },
    { match: "\\b[a-z_][A-Za-z0-9_'-]*", name: "variable.parameter.type.tnix" },
  ],
};

export const tnixGrammar = {
  name: "tnix",
  scopeName: "source.tnix",
  aliases: ["d.tnix"],
  patterns: [
    { include: "#directive" },
    { include: "#comment" },
    { include: "#typeAlias" },
    { include: "#declare" },
    { include: "#signature" },
    { include: "#cast" },
    { include: "#typedBinder" },
    { include: "#string" },
    { include: "#indentedString" },
    { include: "#keyword" },
    { include: "#constant" },
    { include: "#path" },
    { include: "#attribute" },
    { include: "#operator" },
    { include: "#identifier" },
  ],
  repository: {
    typeExpr: typeExpression,
    directive: {
      match: "^\\s*(#)\\s*(@tnix-(?:ignore|expected))\\b.*$",
      captures: {
        1: { name: "comment.line.number-sign.tnix" },
        2: { name: "keyword.control.directive.tnix" },
      },
    },
    comment: {
      patterns: [
        { match: "#.*$", name: "comment.line.number-sign.tnix" },
        { begin: "/\\*", end: "\\*/", name: "comment.block.tnix" },
      ],
    },
    typeAlias: {
      begin: "\\b(type)\\s+([A-Za-z_][A-Za-z0-9_'-]*)((?:\\s+[a-z_][A-Za-z0-9_'-]*)*)\\s*(=)",
      beginCaptures: {
        1: { name: "keyword.other.type.tnix" },
        2: { name: "entity.name.type.alias.tnix" },
        3: { name: "variable.parameter.type.tnix" },
        4: { name: "keyword.operator.type.tnix" },
      },
      end: ";",
      endCaptures: { 0: { name: "punctuation.terminator.type.tnix" } },
      patterns: [{ include: "#typeExpr" }],
    },
    declare: {
      match: "\\b(declare)\\b",
      name: "keyword.other.type.tnix",
    },
    signature: {
      begin: "(::)",
      beginCaptures: { 1: { name: "keyword.operator.annotation.tnix" } },
      end: "(?=;)|(?=\\))",
      patterns: [{ include: "#typeExpr" }],
    },
    typeRecord: {
      begin: "\\{",
      end: "\\}",
      beginCaptures: { 0: { name: "punctuation.definition.type.record.tnix" } },
      endCaptures: { 0: { name: "punctuation.definition.type.record.tnix" } },
      patterns: [
        { include: "#comment" },
        {
          begin: "(\"[^\"]*\"|[A-Za-z_][A-Za-z0-9_'-]*)\\s*(::)",
          beginCaptures: {
            1: { name: "variable.other.property.tnix" },
            2: { name: "keyword.operator.annotation.tnix" },
          },
          end: ";",
          endCaptures: { 0: { name: "punctuation.terminator.type.tnix" } },
          patterns: [{ include: "#typeExpr" }],
        },
      ],
    },
    cast: {
      begin: "\\b(as)\\b",
      beginCaptures: { 1: { name: "keyword.other.type.tnix" } },
      end: "(?=[;)\\]}]|\\bin\\b|\\bthen\\b|\\belse\\b|$)",
      patterns: [{ include: "#typeExpr" }],
    },
    typedBinder: {
      match: "\\(([a-z_][A-Za-z0-9_'-]*)\\s*(::)",
      captures: {
        1: { name: "variable.parameter.tnix" },
        2: { name: "keyword.operator.annotation.tnix" },
      },
    },
    string: {
      begin: "\"",
      end: "\"",
      name: "string.quoted.double.tnix",
      patterns: [
        { match: "\\\\.", name: "constant.character.escape.tnix" },
        { include: "#interpolation" },
      ],
    },
    indentedString: {
      begin: "''",
      end: "''(?!['$\\\\])",
      name: "string.quoted.other.indented.tnix",
      patterns: [
        { match: "''(\\$|'|\\\\.)", name: "constant.character.escape.tnix" },
        { include: "#interpolation" },
      ],
    },
    interpolation: {
      begin: "\\$\\{",
      end: "\\}",
      beginCaptures: { 0: { name: "punctuation.section.embedded.begin.tnix" } },
      endCaptures: { 0: { name: "punctuation.section.embedded.end.tnix" } },
      name: "meta.embedded.tnix",
      patterns: [{ include: "$self" }],
    },
    keyword: {
      patterns: [
        { match: "\\b(let|in|if|then|else|assert|with|rec|inherit|or)\\b", name: "keyword.control.tnix" },
        { match: "\\b(import)\\b", name: "support.function.import.tnix" },
        { match: "\\b(builtins)\\b", name: "support.variable.builtins.tnix" },
      ],
    },
    constant: {
      patterns: [
        { match: "\\b(true|false|null)\\b", name: "constant.language.tnix" },
        { match: "-?\\b\\d+(\\.\\d+)?([eE][+-]?\\d+)?\\b", name: "constant.numeric.tnix" },
      ],
    },
    path: {
      match: "(?:\\.{1,2}|~)?/[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*|<[A-Za-z0-9._+/-]+>",
      name: "string.unquoted.path.tnix",
    },
    attribute: {
      match: "([A-Za-z_][A-Za-z0-9_'-]*|\"[^\"]*\")(?=\\s*=(?!=))",
      name: "variable.other.property.tnix",
    },
    operator: {
      match: "\\+\\+|//|==|!=|<=|>=|&&|\\|\\||->|\\|>|[-+*/<>!?@:=]",
      name: "keyword.operator.tnix",
    },
    identifier: {
      match: "\\b[A-Za-z_][A-Za-z0-9_'-]*",
      name: "variable.other.tnix",
    },
  },
};
