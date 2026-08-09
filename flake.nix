{
  description = "homelab dev shell";

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
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        nativeDeps = with pkgs; [
          fluxcd
          kubernetes-helm
          opentofu
          sops
          talosctl
          kustomize
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          shellHook = ''
            export TALOSCONFIG="$(git rev-parse --show-toplevel)/talos/talosconfig"
          '';

          packages = nativeDeps;
        };
      }
    );
}
