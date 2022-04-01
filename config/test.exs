import Config

config :fete_bot, FeteBot.Application, start_bot: false

config :fete_bot, FeteBot.Repo,
  username: "postgres",
  password: "postgres",
  database: "fetebot_test",
  hostname: "localhost",
  pool_size: 5,
  after_connect: {FeteBot.Repo, :create_public_schema, database: "fetebot_test"}
