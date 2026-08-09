{
  description = "OpenCode Kubernetes runtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            opencode
            git
            openssh
            bash
            curl
            jq
            ripgrep
            findutils
            coreutils
            gnugrep
            gnused
            gawk
            direnv
            nix-direnv
          ];
        };
      });
    };
}
