{ self, lib, inputs, flake-parts-lib, ... }:

let
  inherit (flake-parts-lib)
    mkPerSystemOption;
in
{
  options = {
    perSystem = mkPerSystemOption
      ({ config, self', inputs', pkgs, system, ... }: {
        options = {
          workers.overrideCraneArgs = lib.mkOption {
            type = lib.types.functionTo lib.types.attrs;
            default = _: { };
            description = "Override crane args for the workers package";
          };

          workers.rustToolchain = lib.mkOption {
            type = lib.types.package;
            description = "Rust toolchain to use for the workers package";
            default = (pkgs.rust-bin.fromRustupToolchainFile (self + /rust-toolchain.toml)).override {
              extensions = [
                "rust-src"
                "rust-analyzer"
                "clippy"
              ];
            };
          };

          workers.craneLib = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = (inputs.crane.mkLib pkgs).overrideToolchain config.workers.rustToolchain;
          };

          workers.src = lib.mkOption {
            type = lib.types.path;
            description = "Source directory for the workers package";
            # When filtering sources, we want to allow assets other than .rs files
            # TODO: Don't hardcode these!
            default = lib.cleanSourceWith {
              src = self; # The original, unfiltered source
              filter = path: type:
                (lib.hasSuffix "\.html" path) ||
                (lib.hasInfix "/public/" path) ||
                (lib.hasInfix "/style/" path) ||
                (lib.hasInfix "/src/" path) ||
                (lib.hasInfix "/nix/" path) || # We want the hash to change when nix files change
                (lib.hasInfix "/.sqlx/" path) ||
                # Default filter from crane (allow .rs files)
                (config.workers.craneLib.filterCargoSources path type)
              ;
            };
          };
        };

        config =
          let
            cargoToml = builtins.fromTOML (builtins.readFile (self + /Cargo.toml));
            inherit (cargoToml.package) name version;
            inherit (config.workers) rustToolchain craneLib src;

            # Crane builder for cargo-leptos projects
            craneBuild = rec {
              args = {
                inherit src;
                pname = name;
                version = version;
                buildInputs = [
                  pkgs.cargo-leptos
                  pkgs.dart-sass
                  pkgs.binaryen # Provides wasm-opt
                  pkgs.pkg-config
                  pkgs.openssl
                  pkgs.wasm-bindgen-cli
                ] ++ lib.optionals pkgs.stdenv.isDarwin [
                  pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
                ];
              };

              cargoArtifacts = craneLib.buildDepsOnly args;

              buildArgs = args // {
                SQLX_OFFLINE = "true";
                DATABASE_URL = "";
                inherit cargoArtifacts;
                buildPhaseCargoCommand = "LEPTOS_SITE_PKG_DIR=\"pkg-$(nix-hash .)\" cargo leptos build --release -vvv";
                cargoTestCommand = "";
                cargoExtraArgs = "";
                nativeBuildInputs = [
                  pkgs.makeWrapper
                  pkgs.nix # Provides `nix-hash` which we use for cache busting
                ];
                installPhaseCommand = ''
                  mkdir -p $out/bin
                  cp target/release/${name} $out/bin/
                  cp -r site $out/bin/
                  wrapProgram $out/bin/${name} \
                    --set LEPTOS_SITE_ROOT $out/bin/site
                '';
              };

              package = craneLib.buildPackage (buildArgs // config.workers.overrideCraneArgs buildArgs);

              check = craneLib.cargoClippy (args // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets --all-features -- --deny warnings";
              });

              doc = craneLib.cargoDoc (args // {
                inherit cargoArtifacts;
              });
            };

            rustDevShell = pkgs.mkShell {
              shellHook = ''
                # For rust-analyzer 'hover' tooltips to work.
                export RUST_SRC_PATH="${rustToolchain}/lib/rustlib/src/rust/library";
              '';
              buildInputs = [
                pkgs.libiconv
              ];
              nativeBuildInputs = [
                rustToolchain
              ];
            };
          in
          {
            # Rust package
            packages.${name} = craneBuild.package;
            packages."${name}-doc" = craneBuild.doc;

            checks."${name}-clippy" = craneBuild.check;

            # Rust dev environment
            devShells.${name} = pkgs.mkShell {
              inputsFrom = [
                rustDevShell
              ];
              nativeBuildInputs = with pkgs; [
                cargo-leptos
                dart-sass
                binaryen # Provides wasm-opt
                wasm-bindgen-cli
              ];
            };
          };
      });
  };
}
