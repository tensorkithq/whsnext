{
  description = "whn — realtime audience-controlled story platform";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAll (pkgs:
        let
          pgPort = "57432";

          pg-start = pkgs.writeShellScriptBin "pg-start" ''
            set -e
            if [ ! -d "$PGDATA" ]; then
              initdb --auth=trust --no-locale --encoding=UTF8 --username=postgres
            fi
            pg_ctl start -o "-p $PGPORT -k $PGDATA -c listen_addresses=127.0.0.1" -l "$PGDATA/postgres.log"
          '';

          pg-stop = pkgs.writeShellScriptBin "pg-stop" ''
            pg_ctl stop
          '';

          logs = pkgs.writeShellScriptBin "logs" ''
            mkdir -p "$PWD/.nix-logs"
            files=$(ls "$PWD/.nix-logs"/*.log "$PGDATA/postgres.log" 2>/dev/null)
            if [ -z "$files" ]; then
              echo "no logs yet — pg-start writes $PGDATA/postgres.log; the whn-live tmux session pipes Phoenix into .nix-logs/phoenix.log"
              exit 1
            fi
            exec tail -n 100 -F $files
          '';
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              elixir
              nodejs_24
              ffmpeg
              postgresql_17
              pg-start
              pg-stop
              logs
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.inotify-tools ];

            shellHook = ''
              export MIX_HOME="$PWD/.nix-mix"
              export HEX_HOME="$PWD/.nix-hex"
              export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
              export ERL_AFLAGS="-kernel shell_history enabled"

              export PGPORT="${pgPort}"
              export PGDATA="$PWD/.nix-postgres"
              export PGHOST="127.0.0.1"
              export PGUSER="postgres"

              export PORT=57400
              if [ -f "$PWD/.env" ]; then
                set -a; . "$PWD/.env"; set +a
              fi
            '';
          };
        });
    };
}
