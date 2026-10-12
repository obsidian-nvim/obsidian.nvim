{...}: {
  config = {
    perSystem = {
      config,
      pkgs,
      ...
    }: {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.gnumake
        ];
      };
    };
  };
}
