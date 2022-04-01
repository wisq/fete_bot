import Config

config :fete_bot, FeteBot.Application, start_bot: true

config :fete_bot, FeteBot.Repo,
  username: "postgres",
  password: "postgres",
  database: "fetebot_dev",
  hostname: "localhost",
  pool_size: 5,
  after_connect: {FeteBot.Repo, :create_public_schema, database: "fetebot_dev"}
