# Write your first typed Nix

`.tnix` files are ordinary Nix plus type annotations. Try:

```tnix
type User = { name :: String; age :: Int; };

let
  greet :: User -> String;
  greet = user: "hello ${user.name}";

  alice :: User;
  alice = { name = "alice"; age = 30; };
in greet alice
```

Hover any binding to see its inferred type, and break the program (for
example `age = "thirty";`) to see a diagnostic.

- `.tnix` — implementation files, compiled to plain `.nix`
- `.d.tnix` — declaration files describing existing `.nix` code
- `.nix` — plain Nix files also get completion and diagnostics
