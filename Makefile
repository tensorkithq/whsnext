# Thin wrappers over the nix devshell — usable from a bare shell.
# Inside `nix develop` you can call app-start/app-stop/app-restart/logs directly.

NIX := $(shell command -v nix 2>/dev/null || echo /nix/var/nix/profiles/default/bin/nix)

.PHONY: start stop restart logs test

start:
	$(NIX) develop --command app-start

stop:
	$(NIX) develop --command app-stop

restart:
	$(NIX) develop --command app-restart

logs:
	$(NIX) develop --command logs

test:
	$(NIX) develop --command bash -c 'cd server && mix test'
