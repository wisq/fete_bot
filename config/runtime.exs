import Config
alias FeteBot.Secrets

config :nostrum, token: Secrets.fetch!("DISCORD_BOT_TOKEN")

if config_env() == :prod do
  config :fete_bot, FeteBot.Repo,
    username: Secrets.fetch!("DB_USERNAME"),
    password: Secrets.fetch!("DB_PASSWORD"),
    database: Secrets.fetch!("DB_NAME"),
    # hostname is configured below
    pool_size: 10
end

case System.fetch_env("APP_MODE") do
  {:ok, mode} ->
    # Running inside Docker
    config :fete_bot, FeteBot.Application, start_bot: mode == "bot"
    config :fete_bot, FeteBot.Repo, hostname: Secrets.get("DB_HOST", "host.docker.internal")

  :error ->
    if config_env() == :prod, do: raise("Must set APP_MODE in production environment")
end
