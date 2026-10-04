# Type existing Nix code

You do not have to rewrite anything. Describe an existing `.nix` file with a
`declare` block, either inline or in a `.d.tnix` file next to it:

```tnix
declare "./lib.nix" {
  mkGreeting :: { name :: String; } -> String;
  version :: String;
};
```

Every `import ./lib.nix` is now checked against that surface. Gradual escape
hatches keep untyped code working while you migrate:

- `any` — assignable to and from everything
- `unknown` — safe top type; narrow it with `expr as Type`
- `dynamic` — gradual consistency with every type
