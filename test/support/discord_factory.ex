defmodule FeteBot.Test.DiscordFactory do
  import Bitwise, only: [<<<: 2, bor: 2]
  alias Nostrum.Struct.{Message, User, Guild, Channel}

  def user(changes \\ []) do
    %User{
      id: generate_snowflake()
    }
    |> modify(changes)
  end

  def message(changes \\ []) do
    %Message{
      id: generate_snowflake(),
      channel_id: generate_snowflake(),
      author: user()
    }
    |> modify(changes)
  end

  def guild(changes \\ []) do
    %Guild{
      id: generate_snowflake(),
      owner_id: generate_snowflake()
    }
    |> modify(changes)
  end

  def channel(changes \\ []) do
    %Channel{
      id: generate_snowflake()
    }
    |> modify(changes)
  end

  defp modify(obj, attrs) when is_list(attrs), do: struct!(obj, attrs)

  # start of 2015 in milliseconds
  @discord_epoch 1_420_070_400_000

  def generate_snowflake do
    time = (DateTime.utc_now() |> DateTime.to_unix(:millisecond)) - @discord_epoch
    # If we really cared about uniqueness, we would stick these in an ETS or something.
    # But random should be fine.
    worker = Enum.random(1..32)
    process = Enum.random(1..32)
    incr = Enum.random(1..4096)

    time <<< 22
    |> bor(worker <<< 17)
    |> bor(process <<< 12)
    |> bor(incr)
  end
end
