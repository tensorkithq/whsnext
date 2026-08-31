@sprint:2026-08-31-live-episode-mvp
Feature: Bootable dev stack on pinned ports

  @req:DEV-01 @plan:I @wave:1
  Scenario: Ecto reaches the flake Postgres
    Given the nix devshell with pg-start running on 57432
    When mix ecto.create runs in server/
    Then it exits 0 without a connection error

  @req:DEV-02 @plan:I @wave:1
  Scenario: Phoenix serves on the port Vite proxies to
    Given the nix devshell
    When mix phx.server boots
    Then the boot log shows Bandit listening at 127.0.0.1:57400

  @req:DEV-03 @plan:I @wave:1
  Scenario: FAL_KEY loads from the environment, never from git
    Given a .env file at the repo root containing FAL_KEY
    When a new nix develop shell starts
    Then FAL_KEY is exported in the shell, .env remains gitignored, and .env.example documents the shape

  @req:DEV-04 @plan:I @wave:1
  Scenario: Run instructions exist
    Given the repo README
    When a new contributor follows the Development section
    Then it names nix develop, pg-start, mix setup, mix phx.server, and npm run dev in order
