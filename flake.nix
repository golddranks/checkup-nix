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

            # Let's make it support sqlite by default
            buildPhase = ''
              go build -o ./builds/ -tags sqlite3 ./cmd/...
            '';

            installPhase = ''
              mkdir -p $out/bin/
              cp ./builds/checkup $out/bin/
              mkdir -p $out/share/
              cp -R ./statuspage $out/share/
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
      }) // {
        nixosModules.checkup = { config, lib, pkgs, ... }:
          with lib;
          let checkup_cfg = config.services.checkup; in
          {
            options.services.checkup = {

              enable = mkEnableOption "checkup service";

              every = mkOption {
                type = types.str;
                default = "1m";
              };

              checkers = mkOption {
                type = with types; listOf (attrsOf anything);
                default = [];
                example = ''
                  [
                      {
                          type = "http";
                          endpoint_name = "Test";
                          endpoint_url = "https://example.org";
                      }
                  ]
                '';
              };

              storage = mkOption {
                type = with types; attrsOf anything;
                default = {
                  type = "sqlite3";
                  create = true;
                  dir = "/var/lib/checkup/sqlite.db";
                };
                example = ''
                  {
                      type = "sqlite3";
                      create = true;
                      dsn = "/var/lib/checkup/sqlite.db";
                  }
                '';
              };

              notifiers = mkOption {
                type = with types; listOf (attrsOf anything);
                default = [];
                example = ''
                  [
                      {
                          type = "mailgun";
                          from = "checkup@example.org";
                          to = [ "admin@example.org" ];
                          subject = "Server downtime detected";
                          apikey = "asdfasdf";
                          domain = "example.org";
                      }
                  ]
                '';
              };

              statusPage = mkOption {
                type = with types; nullOr str;
                default = null;
                example = "0.0.0.0:3000";
                description = "Binding address and port for serving a status page. Doesn't poke a hole in the firewall; if you want to expose the status page, we recommend you to use a reverse proxy such as Nginx, as the status page is served as unencrypted HTTP.";
              };

            };
            config = mkIf checkup_cfg.enable {
                users.users.checkup = {
                  description = "Checkup";
                  isSystemUser = true;
                };
                systemd.services.checkup = {
                  description = "checkup";
                  after = [ "network.target" ];
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.ExecStart = "${self.packages.${pkgs.system}.checkup}/bin/checkup -c ${config.environment.etc."checkup.json".source} every ${escapeShellArg checkup_cfg.every}";
                  serviceConfig.User = "checkup";
                  serviceConfig.Restart = "always";
                  serviceConfig.LogsDirectory = "checkup";
                };
                environment.etc."checkup.json".text = builtins.toJSON {
                  checkers = checkup_cfg.checkers;
                  storage = checkup_cfg.storage;
                  notifiers = checkup_cfg.notifiers;
                };
                systemd.services.checkup-status = mkIf (isStr checkup_cfg.statusPage) {
                  description = "checkup status page";
                  after = [ "network.target" ];
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.ExecStart = "${self.packages.${pkgs.system}.checkup}/bin/checkup -c ${config.environment.etc."checkup.json".source} serve --listen ${checkup_cfg.statusPage}";
                  serviceConfig.User = "checkup";
                  serviceConfig.WorkingDirectory = "${self.packages.${pkgs.system}.checkup}/share";
                  serviceConfig.Restart = "always";
                  serviceConfig.LogsDirectory = "checkup";
                  serviceConfig.StateDirectory = "checkup";
                };
            };
          };
      };
}
