import Config

config :fete_bot, FeteBot.Application, start_bot: false

config :fete_bot, FeteBot.Discord, backend: FeteBot.Test.MockDiscord.Backend

config :fete_bot, FeteBot.Repo,
  username: "postgres",
  password: "postgres",
  database: "fetebot_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  after_connect: {FeteBot.Repo, :create_public_schema, database: "fetebot_test"}

# Print only warnings and errors during test
config :logger, level: :warn
