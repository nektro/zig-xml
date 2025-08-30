with import <nixpkgs> {};

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    aflplusplus
  ];

  hardeningDisable = [ "all" ];
}
