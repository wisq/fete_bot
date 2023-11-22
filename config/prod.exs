import Config

# Overridden as needed in config/runtime.exs
config :fete_bot, FeteBot.Application, start_bot: false

# Enabled as needed in config/runtime.exs
config :fete_bot, FeteBot.HealthCheck, port: 8080
