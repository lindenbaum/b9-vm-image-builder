{ sources ? import ./sources.nix }:
with
  { overlay = _: pkgs:
      { niv = import ./sources.nix {};
      };
  };
  import sources.nixpkgs 
  { overlays = [ overlay ] ; config = {}; 
  }

