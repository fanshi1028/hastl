{
  description = "flake";

  inputs.nixpkgs.url = "nixpkgs-unstable";

  inputs.nix-github-actions = {
    url = "github:nix-community/nix-github-actions";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-github-actions }:
    let
      ghcVersion = "98";
      mkHsPackage = pkgs:
        pkgs.haskell.packages."ghc${ghcVersion}".override ({
          overrides = hself: hsuper:
            with pkgs.haskell.lib; {
              testcontainers = dontCheck (markUnbroken
                (overrideSrc hsuper.testcontainers {
                  src = pkgs.fetchFromGitHub {
                    owner = "testcontainers";
                    repo = "testcontainers-hs";
                    rev = "aed0602adeee6e16ce6bc20ad2a381f36a1c154e";
                    sha256 =
                      "sha256-Jo0DJ7T9NX7tJKsligt8JxUbo8leN0ECBmA1alTIDjM=";
                  };
                }));

              monad-metrics = markUnbroken hsuper.monad-metrics;
              scotty = hsuper.scotty_0_22;
              wai-middleware-metrics = dontCheck hsuper.wai-middleware-metrics;
            };
        });
    in {

      packages = builtins.mapAttrs (system: pkgs:
        let hsPackages = mkHsPackage pkgs;
        in {
          default = hsPackages.developPackage {
            root = ./.;
            modifier = drv:
              with pkgs.haskell.lib;
              doBenchmark (appendConfigureFlag drv "-O2");
          };
        }) nixpkgs.legacyPackages;

      devShells = builtins.mapAttrs (system: pkgs:
        let hsPackage = mkHsPackage pkgs;
        in {
          default = hsPackage.shellFor {
            packages = _: [ self.packages.${system}.default ];
            nativeBuildInputs = with pkgs; [
              (haskell-language-server.override {
                supportedGhcVersions = [ ghcVersion ];
                supportedFormatters = [ "ormolu" ];
              })
              haskellPackages.cabal-fmt
              cabal-install
              ghcid
              tailwindcss
            ];
            withHoogle = true;
            doBenchmark = true;
          };
        }) nixpkgs.legacyPackages;

      checks = builtins.mapAttrs (system: pkgs: {
        default = self.packages.${system}.default;
        shell = self.devShells.${system}.default;
      }) nixpkgs.legacyPackages;

      githubActions = nix-github-actions.lib.mkGithubMatrix {
        checks =
          builtins.mapAttrs (_: checks: { inherit (checks) default shell; }) {
            inherit (self.checks) x86_64-linux x86_64-darwin;
          };
        platforms = {
          x86_64-linux = "ubuntu-22.04";
          x86_64-darwin = "macos-13";
        };
      };
    };

  nixConfig = {
    extra-substituters = [ "https://fanshi1028-personal.cachix.org" ];
    extra-trusted-public-keys = [
      "fanshi1028-personal.cachix.org-1:XoynOisskxlhrHM+m5ytvodedJdAo8gKpam/L6/AmBI="
    ];
  };
}
