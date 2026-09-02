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

          app-start = pkgs.writeShellScriptBin "app-start" ''
            set -e
            if tmux has-session -t whn-live 2>/dev/null; then
              echo "already running — tmux attach -t whn-live (logs: nix develop -c logs)"
              exit 0
            fi
            pg_ctl status >/dev/null 2>&1 || pg-start
            mkdir -p "$PWD/.nix-logs"
            NIX_BIN=$(command -v nix)
            tmux new-session -d -s whn-live \
              "cd $PWD && exec $NIX_BIN develop --command bash -c 'cd server && iex -S mix phx.server'"
            tmux pipe-pane -t whn-live -o "cat >> $PWD/.nix-logs/phoenix.log"
            echo -n "waiting for phoenix on 57400 "
            for _ in $(seq 1 60); do
              if ss -tln 2>/dev/null | grep -q ':57400 '; then break; fi
              tmux has-session -t whn-live 2>/dev/null || { echo; echo "session died — tmux capture-pane -t whn-live -p"; exit 1; }
              echo -n "."; sleep 2
            done
            echo " up"
            tmux send-keys -t whn-live 'Whn.Episodes.start!(Whn.Seed.salary_just_entered())' Enter
            echo "episode started (generation begins when the first viewer joins; cycles need 2 voters)"
            echo "live at https://serve.selfbrain.net — console: tmux attach -t whn-live — logs: logs"
          '';

          app-stop = pkgs.writeShellScriptBin "app-stop" ''
            tmux kill-session -t whn-live 2>/dev/null && echo "tmux session killed"
            PID=$(ss -tlnp 2>/dev/null | grep ':57400 ' | grep -oP 'pid=\K[0-9]+' | head -1)
            [ -n "$PID" ] && kill "$PID" && echo "beam $PID killed"
            for _ in $(seq 1 15); do
              ss -tln 2>/dev/null | grep -q ':57400 ' || break
              sleep 1
            done
            echo "app stopped"
          '';

          app-restart = pkgs.writeShellScriptBin "app-restart" ''
            app-stop
            exec app-start
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
              app-start
              app-stop
              app-restart
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
