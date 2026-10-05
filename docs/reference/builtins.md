---
title: Builtins and Registry
description: The built-in type constructors, the names in scope by default, how to type Nix builtins, and the declaration packs shipped in the registry.
---

# Builtins and Registry

## Built-in type constructors

These names are always available in types. Any other capitalized name must be
an alias or comes from a declaration file.

| Name | Kind | Meaning |
| --- | --- | --- |
| `String` | `Type` | strings; string literals such as `"web"` are subtypes |
| `Int` | `Type` | integers |
| `Nat` | `Type` | non-negative integers; `Nat <: Int` |
| `Float` | `Type` | floating-point numbers |
| `Number` | `Type` | any number; `Int <: Number`, `Float <: Number` |
| `Bool` | `Type` | booleans; `true` and `false` are literal subtypes |
| `Null` | `Type` | the type of `null` |
| `Path` | `Type` | path literals such as `./src` |
| `List` | `Type -> Type` | homogeneous lists |
| `Tuple` | `Type -> Type` | fixed heterogeneous lists, written `Tuple [ A B ]` |
| `Vec` | `Type -> Type -> Type` | `Vec n a`: lists of length `n` |
| `Matrix` | `Type -> Type -> Type -> Type` | `Matrix r c a`: rectangular nested lists |
| `Tensor` | `Type -> Type -> Type` | `Tensor [ d1 d2 ... ] a`: rank-n shapes |
| `Range` | `Type -> Type -> Type -> Type` | `Range lo hi base`: inclusive numeric bounds |
| `Unit` | `Type -> Type -> Type` | `Unit "label" base`: phantom units of measure |

The keywords `dynamic`, `unknown` and `any` are types too; see
[gradual typing](../tutorial/gradual.md). Literal types (`"web"`, `8080`, `1.5`,
`true`, `false`) can appear anywhere a type can.

## Names in scope in expressions

Every `.tnix` file starts with two names in scope:

| Name | Default type | Becomes |
| --- | --- | --- |
| `builtins` | `dynamic` | the declared record, once a `declare "builtins" { ... }` block is loaded |
| `import` | `Path -> dynamic` | the declared scheme of the target, when the argument is a path or string literal with a declaration |

Everything else must be bound by `let`, a lambda, `rec`, or a `with` scope.

> [!NOTE]
> **Upcoming.** Nix's global builtins that do not need the `builtins.` prefix
> (`toString`, `map`, `throw`, `derivation`, `baseNameOf`, `isNull`, and
> friends) are being added to the default scope. Until then, write
> `builtins.toString` and so on.

## Typing `builtins`

`builtins` stays `dynamic` until a declaration says otherwise:

```tnix [types/builtins.d.tnix]
declare "builtins" {
  head :: forall a. List a -> a;
  length :: forall a. List a -> Int;
  map :: forall a b. (a -> b) -> List a -> List b;
  toString :: dynamic -> String;
};
```

This is the starter file that `tnix init` writes. Once any declaration for
`"builtins"` is visible in the workspace, `builtins` is a **closed** record:
members that are not declared are `TC0009` errors rather than `dynamic`. Either
declare everything you use, or start from the full pack below.

The target string `"builtins"` is special-cased; it does not name a file. Like
any other target, it may be declared only once per workspace.

## The registry

The repository's [`registry/`](https://github.com/ubugeeei-prod/tnix/tree/main/registry)
directory contains curated declaration packs, in the spirit of DefinitelyTyped.
Copy the files you need into your project, or vendor the directory and list it
in [`declarationPacks`](./config.md#declarationpacks).

### `registry/workspace/`

Declarations for files every project has. These are rebased onto your project
root when loaded through `declarationPacks`.

| File | Declares |
| --- | --- |
| [`builtins.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/workspace/builtins.d.tnix) | about 100 Nix builtins, from `abort` to `zipAttrsWith`, plus helper aliases such as `Predicate a` and `Fold b a` |
| [`flake.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/workspace/flake.d.tnix) | a minimal `flake.nix` shape: `description`, `inputs`, and `outputs :: ResolvedFlakeInputs -> FlakeOutputs` |
| [`tnix.config.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/workspace/tnix.config.d.tnix) | `TnixProjectConfig` for `tnix.config.tnix` |

### `registry/ecosystem/`

Alias-only packs for nixpkgs, NixOS modules and the flake ecosystem. They
declare **types**, not files, so you connect them to your code with an
annotation or your own `declare` block. Load the whole directory:
`nixpkgs-lib` is self-contained, and the other packs build on it (`nixpkgs-pkgs`
on `nixpkgs-lib`, `nixos-modules` on both, the flake packs on all three).

```tnix [tnix.config.tnix]
{
  declarationPacks = [ ./vendor/tnix/registry/ecosystem ];
}
```

```tnix
# Annotate the arguments nixpkgs passes in:
{ lib :: NixpkgsLib, stdenv :: NixpkgsStdenv, fetchFromGitHub :: NixpkgsFetchFromGitHub, ... }:
stdenv.mkDerivation {
  pname = "hello";
  version = "1.0";
  src = fetchFromGitHub { owner = "me"; repo = "hello"; rev = "v1.0"; hash = "sha256-..."; };
  meta.license = lib.licenses.mit;
}
```

```tnix
# Or type a file you import:
declare "./nix/flake-utils.nix" { default :: NixFlakeUtilsFlake; };
```

| File | Main aliases |
| --- | --- |
| [`nixpkgs-lib.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/nixpkgs-lib.d.tnix) | `NixpkgsLib` and one alias per sub-library; `NixpkgsDerivation`, `NixpkgsDerivationCore`, `NixpkgsMeta`, `NixpkgsLicense`, `NixpkgsMaintainer`, `NixpkgsPlatform`, `NixpkgsSystem`, `NixpkgsSourceLike`, `NixpkgsFileset`; module-system values `NixpkgsOptionType a`, `NixpkgsMkOptionArgs a`, `NixpkgsOption a`, `NixpkgsModuleIf a`, `NixpkgsModuleOverride a`, ...; `NixosSystemArgs` / `NixosConfiguration` for `lib.nixosSystem` |
| [`nixpkgs-pkgs.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/nixpkgs-pkgs.d.tnix) | `NixpkgsPkgs`, `NixpkgsStdenv`, `NixpkgsImport`, `NixpkgsImportArgs`, `NixpkgsConfig`; builder arguments `NixpkgsMkDerivationArgs`, `NixpkgsMkShellArgs`, `NixpkgsBuildGoModuleArgs`, `NixpkgsBuildRustPackageArgs`, `NixpkgsBuildNpmPackageArgs`, `NixpkgsBuildPythonPackageArgs`, `NixpkgsWriteShellApplicationArgs`, `NixpkgsSymlinkJoinArgs`, `NixpkgsBuildEnvArgs`; fetchers `NixpkgsFetchFromGitHub`, `NixpkgsFetchUrl`, `NixpkgsFetchZip`, `NixpkgsFetchGit`, `NixpkgsFetchFromGitLab`, `NixpkgsFetchPatch`; `NixpkgsRustPlatform`, `NixpkgsPythonPackages`, `NixpkgsPython`, `NixpkgsHaskellPackageSet`, `NixpkgsDockerTools`, `NixpkgsFormats`, `NixpkgsWriters` |
| [`nixos-modules.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/nixos-modules.d.tnix) | `NixosModule`, `NixosModuleArgs`, `NixosModuleAttrs`, `NixosModuleFunction`, `NixosSystemdService`, `NixosUser` |
| [`flake-ecosystem.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/flake-ecosystem.d.tnix) | `NixFlake`, `NixFlakeOutputs`, `NixFlakeInputSpec`, `NixFlakeApp`, `NixFlakeTemplate`, `NixFlakePerSystem a`, `NixFlakeSystemOutputs a`, `NixFlakeSourceInfo`; `NixpkgsFlake`, `NixFlakeUtilsFlake`, `FlakePartsFlake` / `FlakePartsLib` / `FlakePartsModule` / `FlakePartsPerSystemArgs`, `HomeManagerFlake` / `HomeManagerConfigurationArgs` / `HomeManagerDag`, `NixDarwinFlake` |
| [`community-flakes.d.tnix`](https://github.com/ubugeeei-prod/tnix/blob/main/registry/ecosystem/community-flakes.d.tnix) | `DevenvFlake`, `TreefmtNixFlake`, `PreCommitHooksFlake`, `CraneFlake` / `CraneLib` / `CraneBuildArgs`, `FenixFlake`, `DeployRsFlake`, `NixvimFlake`, `SopsNixFlake`, `AgenixFlake`, `DiskoFlake`, `ColmenaFlake` |

#### What `NixpkgsLib` covers

Every sub-library is reachable both nested and at the top level, exactly as
nixpkgs re-exports it (`lib.attrsets.mapAttrs` and `lib.mapAttrs`; about 460
top-level names). Signatures follow nixpkgs 26.11.

| Sub-library | Alias | Highlights |
| --- | --- | --- |
| `lib.attrsets` | `NixpkgsAttrsetsLib` | `mapAttrs :: forall a b. (String -> a -> b) -> AttrsOf a -> AttrsOf b`, `mapAttrs'`, `mapAttrsToList`, `filterAttrs`, `foldlAttrs`, `genAttrs`, `listToAttrs`, `nameValuePair`, `optionalAttrs`, `recursiveUpdate`, `attrByPath`, `zipAttrsWith`, `cartesianProduct`, `getExe`-style output selectors |
| `lib.lists` | `NixpkgsListsLib` | `map`, `filter`, `foldl'`, `foldr`, `imap0`, `concatMap`, `optional`, `optionals`, `findFirst`, `partition`, `groupBy`, `sort`, `sortOn`, `unique`, `range`, `take`, `drop`, `zipListsWith`, `toposort` |
| `lib.strings` | `NixpkgsStringsLib` | `concatStringsSep`, `concatMapStringsSep`, `optionalString`, `hasPrefix`, `removePrefix`, `splitString`, `trim`, `toUpper`, `escapeShellArg`, `makeBinPath`, `versionAtLeast`, `cmakeFeature`, `mesonBool`, `enableFeature`, `toInt` |
| `lib.trivial` | `NixpkgsTrivialLib` | `id`, `const`, `flip`, `pipe`, `warn`, `warnIf`, `throwIf`, `defaultTo`, `mapNullable`, `importJSON`, `importTOML`, `version`, `boolToString` |
| `lib.options` | `NixpkgsOptionsLib` | `mkOption :: forall a. NixpkgsMkOptionArgs a -> NixpkgsOption a`, `mkEnableOption`, `mkPackageOption`, `literalExpression`, `literalMD`, `showOption`, `getValues` |
| `lib.types` | `NixpkgsTypesLib` | `str`, `int`, `bool`, `port`, `path`, `package`, `lines`, `ints.*`, `numbers.*`, `listOf`, `attrsOf`, `lazyAttrsOf`, `attrsWith`, `nullOr`, `enum`, `either`, `oneOf`, `coercedTo`, `addCheck`, `functionTo`, `submodule`, `submoduleWith`, `deferredModule`, `mkOptionType` |
| `lib.modules` | `NixpkgsModulesLib` | `mkIf`, `mkMerge`, `mkDefault`, `mkForce`, `mkOverride`, `mkOptionDefault`, `mkBefore`, `mkAfter`, `mkOrder`, `mkDefinition`, `evalModules`, `mkRenamedOptionModule`, `mkRemovedOptionModule`, `mkAliasOptionModule`, `importApply` |
| `lib.fixedPoints` | `NixpkgsFixedPointsLib` | `fix`, `fix'`, `extends`, `composeExtensions`, `composeManyExtensions`, `makeExtensible`, `toExtension` |
| `lib.customisation` | `NixpkgsCustomisationLib` | `callPackageWith`, `callPackagesWith`, `makeOverridable`, `makeScope`, `overrideDerivation`, `extendDerivation`, `extendMkDerivation`, `hydraJob` |
| `lib.meta` | `NixpkgsMetaLib` | `getExe`, `getExe'`, `lowPrio`, `hiPrio`, `setPrio`, `addMetaAttrs`, `availableOn`, `getLicenseFromSpdxId` |
| `lib.versions` | `NixpkgsVersionsLib` | `major`, `minor`, `patch`, `majorMinor`, `splitVersion`, `pad` |
| `lib.fileset` | `NixpkgsFilesetLib` | `toSource`, `unions`, `union`, `intersection`, `difference`, `fileFilter`, `gitTracked`, `maybeMissing`, `fromSource` |
| `lib.filesystem`, `lib.path`, `lib.sources` | `NixpkgsFilesystemLib`, `NixpkgsPathLib`, `NixpkgsSourcesLib` | `listFilesRecursive`, `packagesFromDirectoryRecursive`, `pathType`; `path.append`, `path.subpath.*`; `cleanSource`, `cleanSourceWith`, `sourceByRegex` |
| `lib.generators`, `lib.cli` | `NixpkgsGeneratorsLib`, `NixpkgsCliLib` | `toINI`, `toKeyValue`, `toJSON`, `toYAML`, `toLua`, `toPretty`, `mkLuaInline`; `toGNUCommandLine`, `toCommandLineShellGNU` |
| `lib.debug`, `lib.asserts` | `NixpkgsDebugLib`, `NixpkgsAssertsLib` | `traceVal`, `traceSeq`, `runTests`; `assertMsg`, `assertOneOf` |
| `lib.systems` | `NixpkgsSystemsLib` | `flakeExposed`, `elaborate :: String \| NixpkgsAttrs -> NixpkgsPlatform`, `doubles` |
| `lib.licenses`, `lib.maintainers`, `lib.teams`, `lib.platforms` | | `AttrsOf NixpkgsLicense`, `AttrsOf NixpkgsMaintainer`, `AttrsOf NixpkgsTeam`, `NixpkgsSystemDoubles` |
| also | | `lib.gvariant`, `lib.stringsWithDeps`, `lib.derivations`, `lib.flakes`, `lib.nixosSystem`, `lib.extend`; `lib.misc` (deprecated helpers) is reachable but `dynamic` |

#### How the packs model nixpkgs

- **Open library records.** `NixpkgsLib`, its sub-libraries, `NixpkgsPkgs`,
  derivations and platforms end in `...`: a member the pack does not list is
  `dynamic`, not an error, so new nixpkgs functions and packages keep working.
- **Closed argument records with optional fields.** Builder arguments
  (`NixpkgsMkDerivationArgs`, fetcher arguments, `NixpkgsMkOptionArgs`, ...)
  list every documented attribute as optional (`doCheck? :: Bool`) and mark the
  genuinely required ones (`fetchFromGitHub` needs `owner` and `repo`;
  `writeShellApplication` needs `name` and `text`). A wrongly typed attribute
  or a missing required one is an error; extra attributes such as custom
  environment variables are still accepted by width subtyping.
- **`finalAttrs`.** `stdenv.mkDerivation`, `buildGoModule`,
  `rustPlatform.buildRustPackage`, `buildNpmPackage` and
  `buildPythonPackage` accept `NixpkgsArgsOrFinalAttrs Args`, which is
  `Args | (dynamic -> Args)`.
- **Option types carry their value type.** `lib.types.int` is
  `NixpkgsOptionType Int`, `listOf`/`attrsOf`/`nullOr`/`either`/`enum` combine
  them, and `mkOption` relates `type` and `default`:
  `mkOption { type = types.port; default = "80"; }` is rejected,
  `mkOption { type = types.enum [ "a" "b" ]; default = "c"; }` too.
- **Module properties are values.** `mkIf c x` is `NixpkgsModuleIf a`,
  `mkDefault x` is `NixpkgsModuleOverride a`, `mkBefore x` is
  `NixpkgsModuleOrder a`, so you can annotate helpers that build config.
- **Module `config` and `options` are `dynamic`.** Their shape depends on every
  module in the evaluation; `NixosModuleArgs` types `lib`, `pkgs` and
  `modulesPath` instead.
- **Accepting vs producing systems.** Results such as
  `lib.systems.flakeExposed` use the literal union `NixpkgsSystem`; parameters
  take `String`, so `builtins.currentSystem` is accepted.
- **No branching alias cycles.** Package-set variants (`pkgsStatic`,
  `pkgsCross.*`, `extend`) are `dynamic`, and `override`/`overrideAttrs` return
  `NixpkgsDerivationCore`, which keeps the alias graph acyclic.

## Writing your own pack

- Put aliases and `declare` blocks in `.d.tnix` files. A declaration file must
  not contain an expression: one that does breaks analysis for the whole
  workspace with `TD0007`.
- Prefix alias names with the library's name (`Nixpkgs...`, `HomeManager...`).
  All aliases share one namespace per workspace.
- Prefer `dynamic` for parts you have not modeled over guessing; a wrong type is
  worse than an honest `dynamic`.
- Use `forall` for polymorphic members (`map :: forall a b. ...`), and let
  higher-kinded parameters be inferred (`type Functor f = { ... f a ... };`).
