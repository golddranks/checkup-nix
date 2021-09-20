{
  description = "Sourcegraph Checkup";

  inputs.checkup = {
    url = "github:sourcegraph/checkup";
    flake = false;
  };

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, checkup, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: 
      let pkgs = nixpkgs.legacyPackages.${system}; in
      rec {
        packages = flake-utils.lib.flattenTree {
          checkup = pkgs.buildGoModule {
            pname = "checkup";
            version = "2.0.0";

            src = checkup.outPath;

            vendorSha256 = "ZbqY6eaUyaTWH/U3cayKtNza01ez8C0vsdzgGPl8KjI=";

            meta = with nixpkgs.lib; {
              description = "Sourcegraph Checkup";
              homepage = "https://github.com/sourcegraph/checkup";
              license = licenses.mit;
              platforms = platforms.linux ++ platforms.darwin;
            };
          };
        };
        defaultPackage = packages.checkup;
      });
}
