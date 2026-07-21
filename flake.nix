{
  description = "Build the latest Hyprland (via upstream's own flake) and verify this repo's Lua config against it.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hyprland.url = "github:hyprwm/Hyprland";
  };

  nixConfig = {
    extra-substituters = [ "https://hyprland.cachix.org" ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  outputs = { self, nixpkgs, hyprland }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      hyprlandPkg = hyprland.packages.${system}.hyprland;
    in {
      packages.${system}.hyprland-latest = hyprlandPkg;

      # Assumes it's invoked with CWD already at the repo root (true both for
      # a bare `nix run .#verify` from the repo root, and for the Docker
      # wrapper in the Makefile, which sets -w to the mounted repo).
      # Deliberately does NOT shell out to a bare `make` on PATH -- the
      # nixos/nix container image has no `make`, so gnumake is referenced by
      # its Nix store path directly, making this work identically on bare
      # metal or inside the container.
      apps.${system}.verify = {
        type = "app";
        program = toString (pkgs.writeShellScript "verify-latest-hyprland" ''
          set -euo pipefail
          # Hyprland aborts immediately (even for --version) if this isn't
          # set. It just needs to point at a writable directory -- nothing
          # reads or persists from it here.
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$(mktemp -d)}"
          "${hyprlandPkg}/bin/Hyprland" --version
          # --i-am-really-stupid: this runs as root inside the nixos/nix
          # container (a throwaway config-verify sandbox, not a real
          # session), and Hyprland otherwise refuses to start as root.
          exec "${pkgs.gnumake}/bin/make" verify \
            HYPRLAND="${hyprlandPkg}/bin/Hyprland" \
            HYPRLAND_FLAGS=--i-am-really-stupid
        '');
      };
    };
}
