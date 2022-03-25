import Config

config :nostrum,
  token: File.read!(".secrets/discord_bot_token") |> String.trim()

config :fete_bot,
  ecto_repos: [FeteBot.Repo]

config :fete_bot, FeteBot.Repo,
  username: "postgres",
  password: "postgres",
  database: "fetebot",
  hostname: "localhost",
  pool_size: 10,
  after_connect: {FeteBot.Repo, :create_public_schema, database: "fetebot"}
