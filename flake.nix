{
  description = "A post-modern text editor.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , rust-overlay
    , ...
    }:
    let
      inherit (nixpkgs) lib;
      eachSystem = lib.genAttrs lib.systems.flakeExposed;
      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          localSystem.system = system;
          overlays = [
            (import rust-overlay)
            self.overlays.helix
            self.overlays.dev
          ];
        }
      );
      gitRev = self.rev or self.dirtyRev or null;
    in
    {
      packages = eachSystem (system: {
        inherit (pkgsFor.${system}) helix helix-msrv;
        /*
          The default Helix build. Uses the latest stable Rust toolchain, and unstable
          nixpkgs.

          The build inputs can be overridden with the following:

          packages.${system}.default.override { rustPlatform = newPlatform; };

          Overriding a derivation attribute can be done as well:

          packages.${system}.default.overrideAttrs { buildType = "debug"; };
        */
        default = self.packages.${system}.helix;
      });
      checks = lib.mapAttrs
        (
          system: pkgs:
            {
              helix = pkgs.helix.override {
                rustPlatform = pkgs.msrvPlatform;
              };
            }
        )
        pkgsFor;

      # Devshell behavior is preserved.
      devShells = lib.mapAttrs
        (system: pkgs: {
          default =
            let
              commonRustFlagsEnv = "-C link-arg=-fuse-ld=lld -C target-cpu=native --cfg tokio_unstable";
              platformRustFlagsEnv = lib.optionalString pkgs.stdenv.hostPlatform.isLinux "-Clink-arg=-Wl,--no-rosegment";
              helixChecks = (pkgs.helix.override {
                includeGrammarIf = _: false;
              });
            in
            pkgs.mkShell {
              inputsFrom = [
                helixChecks
                helixChecks.passthru.unwrapped
              ];
              nativeBuildInputs = with pkgs;
                [
                  lld
                  cargo-flamegraph
                  rust-bin.nightly.latest.rust-analyzer
                  mdbook
                ]
                ++ (lib.optional (stdenv.isx86_64 && stdenv.hostPlatform.isLinux) cargo-tarpaulin)
                ++ (lib.optional stdenv.hostPlatform.isLinux lldb);
              shellHook = ''
                export RUST_BACKTRACE="1"
                export RUSTFLAGS="''${RUSTFLAGS:-""} ${commonRustFlagsEnv} ${platformRustFlagsEnv}"
              '';
            };
        })
        pkgsFor;

      overlays = {
        helix = final: prev: {
          helix = final.callPackage ./default.nix { inherit gitRev; };
        };

        dev = final: prev: {
          msrvToolchain = prev.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          msrvPlatform = prev.makeRustPlatform {
            cargo = final.msrvToolchain;
            rustc = final.msrvToolchain;
          };
          helix-msrv = final.helix.override {
            rustPlatform = final.msrvPlatform;
          };
        };

        default = self.overlays.helix;
      };
    };
  nixConfig = {
    extra-substituters = [ "https://helix.cachix.org" ];
    extra-trusted-public-keys = [ "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs=" ];
  };
}
