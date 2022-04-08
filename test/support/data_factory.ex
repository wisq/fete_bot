defmodule FeteBot.Test.DataFactory do
  alias FeteBot.Repo
  alias FeteBot.Tracker.Channel
  alias FeteBot.Test.DiscordFactory

  def build_channel(changes \\ []) do
    %Channel{
      channel_id: DiscordFactory.generate_snowflake()
    }
    |> modify(changes)
  end

  def channel!(changes \\ []) do
    build_channel(changes)
    |> Repo.insert!(returning: true)
  end

  defp modify(obj, attrs) when is_list(attrs), do: struct!(obj, attrs)
end
