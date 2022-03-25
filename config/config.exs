import Config

config :nostrum,
  token: File.read!(".secrets/discord_bot_token") |> String.trim()
