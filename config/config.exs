import Config

config :fete_bot,
  ecto_repos: [FeteBot.Repo]

config :fete_bot, FeteBot.Application, start_test: false

config :logger, :console, format: "$date $time [$level] $message\n"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
