{
  description = "tynix: a gradual type system and tooling stack for Nix";

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
      # Builds the tynix Haskell packages on top of any nixpkgs instance. Used
      # for the regular per-system packages, for `overlays.default`, and for
      # the portable release builds (`pkgsStatic` on Linux).
      mkTynix =
        pkgs:
        let
          haskellLib = pkgs.haskell.lib.compose;
          # The core test suites read two things from outside the package:
          # the bundled declaration registry, and the diagnostic-code catalogue
          # they hold the compiler to. Both are copied in so `nix flake check`
          # runs the same suite `cabal test` does.
          tynixCoreSource = pkgs.buildPackages.runCommand "tynix-core-source" { } ''
            mkdir -p "$out"
            cp -R ${./packages/tynix-core}/. "$out"/
            chmod -R u+w "$out"
            cp -R ${./registry} "$out/registry"
            mkdir -p "$out/docs"
            cp ${./docs/diagnostics.md} "$out/docs/diagnostics.md"
          '';
          haskellPackages = pkgs.haskellPackages.extend (
            hfinal: _: {
              "tynix-core" = hfinal.callCabal2nix "tynix-core" tynixCoreSource { };
              "tynix-cli" = hfinal.callCabal2nix "tynix-cli" ./packages/tynix-cli { };
              "tynix-lsp" = hfinal.callCabal2nix "tynix-lsp" ./packages/tynix-lsp { };
            }
          );
          tynix = haskellPackages."tynix-cli";
          tynix-lsp = haskellPackages."tynix-lsp";
        in
        {
          inherit
            haskellLib
            haskellPackages
            tynix
            tynix-lsp
            ;
          tynix-core = haskellPackages."tynix-core";
          tynix-toolchain = pkgs.symlinkJoin {
            name = "tynix-toolchain-${tynix.version}";
            paths = [
              (haskellLib.justStaticExecutables tynix)
              (haskellLib.justStaticExecutables tynix-lsp)
            ];
            meta = {
              description = "tynix CLI and language server";
              mainProgram = "tynix";
            };
          };
        };

      overlay = final: _prev: {
        inherit (mkTynix final) tynix tynix-lsp tynix-toolchain;
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
          cfg = config.programs.tynix;
        in
        {
          options.programs.tynix = {
            enable = lib.mkEnableOption "the tynix toolchain (tynix CLI and tynix-lsp)";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.tynix-toolchain;
              defaultText = lib.literalExpression "tynix.packages.\${pkgs.stdenv.hostPlatform.system}.tynix-toolchain";
              description = "The tynix toolchain package to install.";
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
        tynixSet = mkTynix pkgs;
        inherit (tynixSet) haskellLib;
        tynixCore = tynixSet.tynix-core;
        tynixCli = tynixSet.tynix;
        tynixLsp = tynixSet.tynix-lsp;
        tynixToolchain = tynixSet.tynix-toolchain;
        tynixCoreChecked = haskellLib.doCheck tynixCore;
        tynixCliChecked = haskellLib.doCheck tynixCli;
        tynixLspChecked = haskellLib.doCheck tynixLsp;

        # ---------------------------------------------------------------
        # Portable release binaries
        #
        # The archives attached to GitHub releases (and installed by
        # https://tynix.dev/install.sh) must run on machines without Nix.
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
              staticSet = mkTynix pkgs.pkgsStatic;
              portable = drv: haskellLib.justStaticExecutables (haskellLib.dontCheck drv);
            in
            {
              tynix = portable staticSet.tynix;
              tynix-lsp = portable staticSet.tynix-lsp;
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
              tynix = portable tynixCli;
              tynix-lsp = portable tynixLsp;
            };

        releaseBundle =
          pkgs.runCommand "tynix-release-bundle-${tynixCli.version}"
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
                install -m 0755 ${portableExecutables.tynix}/bin/tynix "$out/bin/tynix"
                install -m 0755 ${portableExecutables.tynix-lsp}/bin/tynix-lsp "$out/bin/tynix-lsp"
              ''
              + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                for bin in "$out/bin/tynix" "$out/bin/tynix-lsp"; do
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
                for bin in "$out/bin/tynix" "$out/bin/tynix-lsp"; do
                  for ref in $(grep -aoE '/nix/store/[a-z0-9]{32}-[^/[:space:]"]+' "$bin" | sort -u); do
                    remove-references-to -t "$ref" "$bin"
                  done
                done
              ''
              + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                for bin in "$out/bin/tynix" "$out/bin/tynix-lsp"; do
                  codesign -f -s - "$bin"
                done
              ''
              + ''
                # Verify the bundle is self-contained and starts.
                for bin in "$out/bin/tynix" "$out/bin/tynix-lsp"; do
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
          pkgs.runCommand "tynix-version-metadata-check" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
            ''
              export HOME="$TMPDIR"
              workspace="$TMPDIR/version-check"
              mkdir -p "$workspace/scripts" "$workspace/editors/vscode" "$workspace/packages/tynix-core" "$workspace/packages/tynix-cli" "$workspace/packages/tynix-lsp"
              cp ${./scripts/check-version-sync.ts} "$workspace/scripts/check-version-sync.ts"
              cp ${./package.json} "$workspace/package.json"
              cp ${./CHANGELOG.md} "$workspace/CHANGELOG.md"
              cp ${./editors/vscode/package.json} "$workspace/editors/vscode/package.json"
              cp ${./packages/tynix-core/tynix-core.cabal} "$workspace/packages/tynix-core/tynix-core.cabal"
              cp ${./packages/tynix-cli/tynix-cli.cabal} "$workspace/packages/tynix-cli/tynix-cli.cabal"
              cp ${./packages/tynix-lsp/tynix-lsp.cabal} "$workspace/packages/tynix-lsp/tynix-lsp.cabal"
              cd "$workspace"
              node --experimental-strip-types ./scripts/check-version-sync.ts
              touch "$out"
            '';

        cliSmokeCheck =
          pkgs.runCommand "tynix-cli-smoke-check"
            {
              nativeBuildInputs = [
                tynixCli
                tynixLsp
              ];
            }
            ''
              export HOME="$TMPDIR"
              tynix --version >/dev/null
              tynix-lsp --version >/dev/null
              touch "$out"
            '';

        repoFixturesCheck =
          pkgs.runCommand "tynix-repo-fixtures-check" { nativeBuildInputs = [ tynixCli ]; }
            ''
              export HOME="$TMPDIR"
              cd ${self}
              tynix check ./dogfood/flake-surface.tynix >/dev/null
              tynix check-project ./examples --format json >/dev/null
              touch "$out"
            '';

        # Lints docs/public/install.sh (served at https://tynix.dev/install.sh)
        # and runs it end to end against a fake release directory, so the
        # curl | sh path is exercised without the network.
        installScriptCheck =
          pkgs.runCommand "tynix-install-script-check"
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
              sh ${./scripts/test-install-script.sh} ${./docs/public/install.sh} ${tynixToolchain}/bin dash
              touch "$out"
            '';

        # Evaluates the NixOS and Home Manager modules against stub option
        # sets and asserts `programs.tynix.enable` installs the toolchain.
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
                        programs.tynix.enable = true;
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
          pkgs.runCommand "tynix-modules-check"
            {
              expected = toString [ tynixToolchain ];
              nixos = toString installed.nixos;
              homeManager = toString installed.home-manager;
            }
            ''
              for actual in "$nixos" "$homeManager"; do
                if [ "$actual" != "$expected" ]; then
                  echo "programs.tynix.enable installed '$actual', expected '$expected'" >&2
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
          default = tynixToolchain;
          tynix = tynixCli;
          tynix-lsp = tynixLsp;
          tynix-core = tynixCore;
          tynix-toolchain = tynixToolchain;
          # Self-contained binaries for the GitHub release archives. Only
          # meaningful on the release targets: x86_64/aarch64 Linux and macOS.
          release-bundle = releaseBundle;
        };

        checks = {
          tynix-core-tests = tynixCoreChecked;
          tynix-cli-tests = tynixCliChecked;
          tynix-lsp-tests = tynixLspChecked;
          version-metadata = versionMetadataCheck;
          cli-smoke = cliSmokeCheck;
          repo-fixtures = repoFixturesCheck;
          install-script = installScriptCheck;
          modules = modulesCheck;
        };

        apps = {
          default = self.apps.${system}.tynix;
          tynix = {
            type = "app";
            program = "${tynixCli}/bin/tynix";
            meta.description = "tynix CLI";
          };
          tynix-lsp = {
            type = "app";
            program = "${tynixLsp}/bin/tynix-lsp";
            meta.description = "tynix language server";
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
            echo "tynix dev shell ready"
            echo "  - Haskell: cabal / ghc / hls"
            echo "  - Tasks: pnpm / vp"
            echo "  - Editors: Node.js / Rust"
          '';
        };
      }
    );
}
