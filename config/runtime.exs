import Config
alias FeteBot.Secrets

unless config_env() == :test do
  config :nostrum, token: Secrets.fetch!("DISCORD_BOT_TOKEN")
end

if config_env() == :prod do
  config :fete_bot, FeteBot.Repo,
    url: Secrets.fetch!("DATABASE_URL"),
    socket_options: [:inet6],
    pool_size: 10
end

case System.fetch_env("APP_MODE") do
  {:ok, mode} ->
    # Running inside Docker
    config :fete_bot, FeteBot.Application, start_bot: mode == "bot"

  :error ->
    if config_env() == :prod, do: raise("Must set APP_MODE in production environment")
end
