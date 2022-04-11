defmodule FeteBot.Test.DataFactory do
  alias FeteBot.Repo
  alias FeteBot.Tracker.Channel
  alias FeteBot.Test.DiscordFactory

  def build(:channel) do
    %Channel{
      channel_id: DiscordFactory.generate_snowflake()
    }
  end

  def build(factory_name, attributes) do
    factory_name |> build() |> struct!(attributes)
  end

  def insert!(factory_name, attributes \\ []) do
    factory_name |> build(attributes) |> Repo.insert!(returning: true)
  end
end
