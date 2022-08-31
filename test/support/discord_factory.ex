defmodule FeteBot.Test.DiscordFactory do
  import Bitwise, only: [<<<: 2, bor: 2]
  alias Nostrum.Struct.{Message, User, Guild, Guild.Member, Guild.Role, Channel, Event, Emoji}

  def build(:user) do
    %User{
      id: generate_snowflake()
    }
  end

  def build(:message) do
    %Message{
      id: generate_snowflake(),
      channel_id: generate_snowflake(),
      author: build(:user),
      member: build(:member)
    }
  end

  def build(:guild) do
    %Guild{
      id: generate_snowflake(),
      owner_id: generate_snowflake(),
      roles: %{}
    }
  end

  def build(:member) do
    %Member{
      roles: []
    }
  end

  def build(:role) do
    %Role{
      id: generate_snowflake(),
      permissions: 0
    }
  end

  def build(:channel) do
    %Channel{
      id: generate_snowflake()
    }
  end

  def build(:emoji) do
    %Emoji{}
  end

  def build(:message_reaction_add_event) do
    %Event.MessageReactionAdd{
      channel_id: generate_snowflake(),
      message_id: generate_snowflake(),
      user_id: generate_snowflake()
    }
  end

  def build(factory_name, attributes) do
    factory_name |> build() |> struct!(attributes)
  end

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
