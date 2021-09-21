{
  description = "Sourcegraph Checkup";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs?rev=9d0a8da8691c0f8f4831e87efee767397cce06d5";

  inputs.checkup = {
    url = "github:sourcegraph/checkup";
    flake = false;
  };

  inputs.systemd-nix.url = "github:serokell/systemd-nix";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, checkup, systemd-nix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: 
      let pkgs = nixpkgs.legacyPackages.${system}; in
      rec {
        packages = flake-utils.lib.flattenTree {
          checkup = pkgs.buildGoModule {

            preCheck = ''
              patchShebangs ./check/exec/testdata/exec.sh
            '';

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
        apps.checkup = flake-utils.lib.mkApp { drv = packages.checkup; };
        defaultApp = apps.checkup;
        nixosModule = { config, lib, pkgs, ... }:
          with lib;
          let checkup_cfg = config.services.checkup; in
          {
            options.services.checkup = {
              enable = mkEnableOption "checkup service";
              every = mkOption {
                type = types.str;
                default = "1m";
              };
              config = mkOption {
                type = with types; nullOr lines;
                default = null;
                example = ''
                  {
                      "checkers": [
                          {
                              "type": "http",
                              "endpoint_name": "Test",
                              "endpoint_url": "https://example.org"
                          },
                      ],
                      "storage": {
                          "type": "fs",
                          "dir": "/var/checkup/storage"
                      },
                      "notifiers": [
                          {
                              "type": "mailgun",
                              "from": "checkup@example.org",
                              "to": [ "admin@example.org" ],
                              "subject": "Server downtime detected",
                              "apikey": "asdfasdf",
                              "domain": "example.org"
                          }
                      ]
                  }
                '';
                description = ''
                  JSON-based config file for Checkup.
                '';
              };
            };
            config = mkIf checkup_cfg.enable {
              users.users.checkup = {
                description = "Checkup";
                isSystemUser = true;
              };
              environment.etc."checkup.json".text = if isString checkup_cfg.config
                then checkup_cfg.config
                else (''
                  {
                      "checkers": [],
                      "storage": {
                          "type": "fs",
                          "dir": "/var/checkup/storage"
                      },
                      "notifiers": []
                  }
                '');
              systemd.services.checkup = {
                description = "checkup";
                after = [ "network.target" ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig.ExecStart = "${checkup}/bin/checkup -c ${environment.etc."checkup.json".source} every ${escapeShellArg checkup_cfg.every}";
                serviceConfig.WorkingDirectory = "/var/checkup";
                serviceConfig.User = "checkup";
                serviceConfig.Restart = "always";
              };
            };
          };
      });
}
