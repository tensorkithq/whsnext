# Dev environment

## Pin the toolchain in a Nix devshell

The flake pins Elixir and OTP, Node, ffmpeg, and Postgres. Postgres runs on its own port with a repo-local data directory and start and stop helpers, so it never collides with a system install.

## Phoenix reads `PORT` at runtime

Export `PORT` from the devshell so it matches the web proxy target. Keep the same default in `dev.exs` and `runtime.exs`, or the two drift apart.

## Secrets in a gitignored `.env`

The devshell sources `.env` on entry, and `.env.example` documents the keys. This also leaks into tests, so reset provider variables at suite start. See [Elixir and Phoenix](elixir-phoenix.md).

## esbuild's install script can be blocked

esbuild fetches its platform binary in a postinstall script. When the package manager gates install scripts, esbuild installs without its binary and Vite fails. The first web scaffold allowed it with an `allowScripts` entry for the pinned esbuild version in `package.json`. The current scaffold no longer carries that entry, so add it back if the error returns.
