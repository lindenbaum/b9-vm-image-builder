self: super:
{
  b9c = self.pkgs.callPackage ./b9c.nix {};
  haskellPackages = super.haskellPackages.override {
    overrides = hself: hsuper: {
      b9 = import ./b9.nix { inherit (super) nix-gitignore; haskellPackages = hsuper; };
    };
  };
}
