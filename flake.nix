{
  description = "tnix: a gradual type system and tooling stack for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      # Builds the tnix Haskell packages on top of any nixpkgs instance. Used
      # for the regular per-system packages, for `overlays.default`, and for
      # the portable release builds (`pkgsStatic` on Linux).
      mkTnix =
        pkgs:
        let
          haskellLib = pkgs.haskell.lib.compose;
          # The core test suites read two things from outside the package:
          # the bundled declaration registry, and the diagnostic-code catalogue
          # they hold the compiler to. Both are copied in so `nix flake check`
          # runs the same suite `cabal test` does.
          tnixCoreSource = pkgs.buildPackages.runCommand "tnix-core-source" { } ''
            mkdir -p "$out"
            cp -R ${./packages/tnix-core}/. "$out"/
            chmod -R u+w "$out"
            cp -R ${./registry} "$out/registry"
            mkdir -p "$out/docs"
            cp ${./docs/diagnostics.md} "$out/docs/diagnostics.md"
          '';
          haskellPackages = pkgs.haskellPackages.extend (
            hfinal: _: {
              "tnix-core" = hfinal.callCabal2nix "tnix-core" tnixCoreSource { };
              "tnix-cli" = hfinal.callCabal2nix "tnix-cli" ./packages/tnix-cli { };
              "tnix-lsp" = hfinal.callCabal2nix "tnix-lsp" ./packages/tnix-lsp { };
            }
          );
          tnix = haskellPackages."tnix-cli";
          tnix-lsp = haskellPackages."tnix-lsp";
        in
        {
          inherit
            haskellLib
            haskellPackages
            tnix
            tnix-lsp
            ;
          tnix-core = haskellPackages."tnix-core";
          tnix-toolchain = pkgs.symlinkJoin {
            name = "tnix-toolchain-${tnix.version}";
            paths = [
              (haskellLib.justStaticExecutables tnix)
              (haskellLib.justStaticExecutables tnix-lsp)
            ];
            meta = {
              description = "tnix CLI and language server";
              mainProgram = "tnix";
            };
          };
        };

      overlay = final: _prev: {
        inherit (mkTnix final) tnix tnix-lsp tnix-toolchain;
      };

      # Shared by the NixOS / nix-darwin and Home Manager modules.
      mkModule =
        installAttr:
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.tnix;
        in
        {
          options.programs.tnix = {
            enable = lib.mkEnableOption "the tnix toolchain (tnix CLI and tnix-lsp)";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.tnix-toolchain;
              defaultText = lib.literalExpression "tnix.packages.\${pkgs.stdenv.hostPlatform.system}.tnix-toolchain";
              description = "The tnix toolchain package to install.";
            };
          };
          config = lib.mkIf cfg.enable (lib.setAttrByPath installAttr [ cfg.package ]);
        };
    in
    {
      overlays.default = overlay;

      nixosModules.default = mkModule [
        "environment"
        "systemPackages"
      ];
      darwinModules.default = self.nixosModules.default;
      homeManagerModules.default = mkModule [
        "home"
        "packages"
      ];
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (pkgs) lib;

        haskellPackages = pkgs.haskellPackages;
        tnixSet = mkTnix pkgs;
        inherit (tnixSet) haskellLib;
        tnixCore = tnixSet.tnix-core;
        tnixCli = tnixSet.tnix;
        tnixLsp = tnixSet.tnix-lsp;
        tnixToolchain = tnixSet.tnix-toolchain;
        tnixCoreChecked = haskellLib.doCheck tnixCore;
        tnixCliChecked = haskellLib.doCheck tnixCli;
        tnixLspChecked = haskellLib.doCheck tnixLsp;

        # ---------------------------------------------------------------
        # Portable release binaries
        #
        # The archives attached to GitHub releases (and installed by
        # https://tnix.dev/install.sh) must run on machines without Nix.
        #
        # * Linux: fully static musl executables from `pkgsStatic`.
        # * macOS: fully static linking is not possible, so GMP is linked
        #   statically and the two remaining Nix-provided dylibs, which are
        #   Apple's own libiconv and libffi forks, are repointed at the copies
        #   that ship in /usr/lib. The binaries are then ad-hoc re-signed.
        #
        # `release-bundle` fails to build if the result still references
        # /nix/store or is not self-contained.
        # ---------------------------------------------------------------
        portableExecutables =
          if pkgs.stdenv.hostPlatform.isLinux then
            let
              staticSet = mkTnix pkgs.pkgsStatic;
              portable = drv: haskellLib.justStaticExecutables (haskellLib.dontCheck drv);
            in
            {
              tnix = portable staticSet.tnix;
              tnix-lsp = portable staticSet.tnix-lsp;
            }
          else
            let
              # Link GMP statically: hand the archive to ld64 explicitly so it
              # satisfies the GMP symbols before the `-lgmp` that ghc-bignum
              # adds, then drop the dylib that is left unused.
              gmpStatic = pkgs.gmp.override { withStatic = true; };
              portable =
                drv:
                lib.pipe drv [
                  haskellLib.dontCheck
                  (haskellLib.appendConfigureFlags [
                    "--ghc-option=-optl-Wl,-force_load,${gmpStatic}/lib/libgmp.a"
                    "--ghc-option=-optl-Wl,-dead_strip_dylibs"
                  ])
                  haskellLib.justStaticExecutables
                ];
            in
            {
              tnix = portable tnixCli;
              tnix-lsp = portable tnixLsp;
            };

        releaseBundle =
          pkgs.runCommand "tnix-release-bundle-${tnixCli.version}"
            {
              nativeBuildInputs = [
                pkgs.file
                pkgs.buildPackages.removeReferencesTo
              ]
              ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                pkgs.cctools
                pkgs.darwin.sigtool
              ];
              # The output is a pair of standalone binaries; it must not keep
              # anything from the store alive.
              allowedReferences = [ ];
              passthru = {
                inherit portableExecutables;
              };
            }
            (
              ''
                mkdir -p "$out/bin"
                install -m 0755 ${portableExecutables.tnix}/bin/tnix "$out/bin/tnix"
                install -m 0755 ${portableExecutables.tnix-lsp}/bin/tnix-lsp "$out/bin/tnix-lsp"
              ''
              + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                for bin in "$out/bin/tnix" "$out/bin/tnix-lsp"; do
                  for dep in $(otool -L "$bin" | tail -n +2 | awk '{print $1}' | grep '^/nix/store/' || true); do
                    case "$dep" in
                      */libiconv.2.dylib) replacement=/usr/lib/libiconv.2.dylib ;;
                      */libffi.*dylib) replacement=/usr/lib/libffi.dylib ;;
                      *)
                        echo "release-bundle: $bin links unexpected store library $dep" >&2
                        exit 1
                        ;;
                    esac
                    echo "release-bundle: $bin: $dep -> $replacement"
                    install_name_tool -change "$dep" "$replacement" "$bin"
                  done
                  for rpath in $(otool -l "$bin" | awk '$1 == "cmd" && $2 == "LC_RPATH" {getline; getline; print $2}' | grep '^/nix/store/' || true); do
                    install_name_tool -delete_rpath "$rpath" "$bin"
                  done
                done
              ''
              + ''
                # Leftover store path strings (Paths_* data dirs, toolchain
                # paths baked into the RTS) are never dereferenced at runtime;
                # scrub them so the bundle has no store references.
                for bin in "$out/bin/tnix" "$out/bin/tnix-lsp"; do
                  for ref in $(grep -aoE '/nix/store/[a-z0-9]{32}-[^/[:space:]"]+' "$bin" | sort -u); do
                    remove-references-to -t "$ref" "$bin"
                  done
                done
              ''
              + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                for bin in "$out/bin/tnix" "$out/bin/tnix-lsp"; do
                  codesign -f -s - "$bin"
                done
              ''
              + ''
                # Verify the bundle is self-contained and starts.
                for bin in "$out/bin/tnix" "$out/bin/tnix-lsp"; do
                  file "$bin"
              ''
              + (
                if pkgs.stdenv.hostPlatform.isDarwin then
                  ''
                    otool -L "$bin"
                    if otool -L "$bin" | tail -n +2 | grep -Ev '^[[:space:]]+(/usr/lib/|/System/Library/)'; then
                      echo "release-bundle: $bin depends on libraries outside /usr/lib and /System" >&2
                      exit 1
                    fi
                  ''
                else
                  ''
                    if ! file "$bin" | grep -Eq 'statically linked|static-pie linked'; then
                      echo "release-bundle: $bin is not statically linked" >&2
                      exit 1
                    fi
                  ''
              )
              + ''
                  HOME="$TMPDIR" "$bin" --version
                done
              ''
            );

        versionMetadataCheck =
          pkgs.runCommand "tnix-version-metadata-check" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
            ''
              export HOME="$TMPDIR"
              workspace="$TMPDIR/version-check"
              mkdir -p "$workspace/scripts" "$workspace/editors/vscode" "$workspace/packages/tnix-core" "$workspace/packages/tnix-cli" "$workspace/packages/tnix-lsp"
              cp ${./scripts/check-version-sync.ts} "$workspace/scripts/check-version-sync.ts"
              cp ${./package.json} "$workspace/package.json"
              cp ${./CHANGELOG.md} "$workspace/CHANGELOG.md"
              cp ${./editors/vscode/package.json} "$workspace/editors/vscode/package.json"
              cp ${./packages/tnix-core/tnix-core.cabal} "$workspace/packages/tnix-core/tnix-core.cabal"
              cp ${./packages/tnix-cli/tnix-cli.cabal} "$workspace/packages/tnix-cli/tnix-cli.cabal"
              cp ${./packages/tnix-lsp/tnix-lsp.cabal} "$workspace/packages/tnix-lsp/tnix-lsp.cabal"
              cd "$workspace"
              node --experimental-strip-types ./scripts/check-version-sync.ts
              touch "$out"
            '';

        cliSmokeCheck =
          pkgs.runCommand "tnix-cli-smoke-check"
            {
              nativeBuildInputs = [
                tnixCli
                tnixLsp
              ];
            }
            ''
              export HOME="$TMPDIR"
              tnix --version >/dev/null
              tnix-lsp --version >/dev/null
              touch "$out"
            '';

        repoFixturesCheck =
          pkgs.runCommand "tnix-repo-fixtures-check" { nativeBuildInputs = [ tnixCli ]; }
            ''
              export HOME="$TMPDIR"
              cd ${self}
              tnix check ./dogfood/flake-surface.tnix >/dev/null
              tnix check-project ./examples --format json >/dev/null
              touch "$out"
            '';

        # Lints docs/public/install.sh (served at https://tnix.dev/install.sh)
        # and runs it end to end against a fake release directory, so the
        # curl | sh path is exercised without the network.
        installScriptCheck =
          pkgs.runCommand "tnix-install-script-check"
            {
              nativeBuildInputs = [
                pkgs.shellcheck
                pkgs.curl
                pkgs.dash
              ];
            }
            ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              shellcheck --shell=sh ${./docs/public/install.sh}
              sh ${./scripts/test-install-script.sh} ${./docs/public/install.sh} ${tnixToolchain}/bin dash
              touch "$out"
            '';

        # Evaluates the NixOS and Home Manager modules against stub option
        # sets and asserts `programs.tnix.enable` installs the toolchain.
        modulesCheck =
          let
            evalModule =
              module: installAttr:
              let
                config =
                  (lib.evalModules {
                    modules = [
                      module
                      {
                        options = lib.setAttrByPath installAttr (
                          lib.mkOption {
                            type = lib.types.listOf lib.types.package;
                            default = [ ];
                          }
                        );
                      }
                      {
                        programs.tnix.enable = true;
                        _module.args.pkgs = pkgs;
                      }
                    ];
                  }).config;
              in
              lib.getAttrFromPath installAttr config;
            installed = {
              nixos = evalModule self.nixosModules.default [
                "environment"
                "systemPackages"
              ];
              home-manager = evalModule self.homeManagerModules.default [
                "home"
                "packages"
              ];
            };
          in
          pkgs.runCommand "tnix-modules-check"
            {
              expected = toString [ tnixToolchain ];
              nixos = toString installed.nixos;
              homeManager = toString installed.home-manager;
            }
            ''
              for actual in "$nixos" "$homeManager"; do
                if [ "$actual" != "$expected" ]; then
                  echo "programs.tnix.enable installed '$actual', expected '$expected'" >&2
                  exit 1
                fi
              done
              touch "$out"
            '';

        vp = pkgs.writeShellScriptBin "vp" ''
          case "''${1-}" in
            ide|cli)
              command="$1"
              shift
              repo_root="$PWD"
              if command -v git >/dev/null 2>&1; then
                maybe_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
                if [ -n "$maybe_root" ] && [ -f "$maybe_root/flake.nix" ]; then
                  repo_root="$maybe_root"
                fi
              fi
              exec ${pkgs.nodejs_24}/bin/node --experimental-strip-types "$repo_root/scripts/install-$command.ts" "$@"
              ;;
          esac

          if [ -x "$PWD/node_modules/.bin/vp" ]; then
            exec "$PWD/node_modules/.bin/vp" "$@"
          fi

          exec ${pkgs.pnpm}/bin/pnpm dlx vite-plus "$@"
        '';
      in
      {
        formatter = pkgs.nixfmt-rfc-style;

        packages = {
          default = tnixToolchain;
          tnix = tnixCli;
          tnix-lsp = tnixLsp;
          tnix-core = tnixCore;
          tnix-toolchain = tnixToolchain;
          # Self-contained binaries for the GitHub release archives. Only
          # meaningful on the release targets: x86_64/aarch64 Linux and macOS.
          release-bundle = releaseBundle;
        };

        checks = {
          tnix-core-tests = tnixCoreChecked;
          tnix-cli-tests = tnixCliChecked;
          tnix-lsp-tests = tnixLspChecked;
          version-metadata = versionMetadataCheck;
          cli-smoke = cliSmokeCheck;
          repo-fixtures = repoFixturesCheck;
          install-script = installScriptCheck;
          modules = modulesCheck;
        };

        apps = {
          default = self.apps.${system}.tnix;
          tnix = {
            type = "app";
            program = "${tnixCli}/bin/tnix";
            meta.description = "tnix CLI";
          };
          tnix-lsp = {
            type = "app";
            program = "${tnixLsp}/bin/tnix-lsp";
            meta.description = "tnix language server";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [
            haskellPackages.ghc
            pkgs.cabal-install
            pkgs.haskell-language-server
            pkgs.fourmolu
            pkgs.hlint
            pkgs.typos
            pkgs.neovim
            pkgs.pkg-config
            pkgs.zlib
            pkgs.nodejs_24
            pkgs.pnpm
            pkgs.rustc
            pkgs.cargo
            pkgs.rust-analyzer
            pkgs.tree-sitter
            pkgs.git
            pkgs.shellcheck
            vp
          ];

          shellHook = ''
            export LANG=C.UTF-8
            export LC_ALL=C.UTF-8
            echo "tnix dev shell ready"
            echo "  - Haskell: cabal / ghc / hls"
            echo "  - Tasks: pnpm / vp"
            echo "  - Editors: Node.js / Rust"
          '';
        };
      }
    );
}
