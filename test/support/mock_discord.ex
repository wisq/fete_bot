defmodule FeteBot.Test.MockDiscord do
  @mock FeteBot.Test.MockDiscord
  defmodule Backend do
    @mock FeteBot.Test.MockDiscord
    alias FeteBot.Test.DiscordFactory

    def create_message(channel_id, options) do
      mock(
        :create_message,
        {channel_id, options},
        fn _ -> {:ok, DiscordFactory.message(channel_id: channel_id)} end
      )
    end

    def edit_message(channel_id, message_id, options) do
      mock(
        :edit_message,
        {channel_id, message_id, options},
        fn _ -> {:ok, DiscordFactory.message(channel_id: channel_id, message_id: message_id)} end
      )
    end

    def delete_message(channel_id, message_id),
      do: mock(:delete_message, {channel_id, message_id})

    def get_reactions(channel_id, message_id, emoji),
      do: mock(:get_reactions, {channel_id, message_id, emoji}, fn _ -> {:ok, []} end)

    def create_reaction(channel_id, message_id, emoji),
      do: mock(:create_reaction, {channel_id, message_id, emoji})

    def delete_reaction(channel_id, message_id, emoji),
      do: mock(:delete_reaction, {channel_id, message_id, emoji})

    def delete_user_reaction(channel_id, message_id, emoji, user_id),
      do: mock(:delete_user_reaction, {channel_id, message_id, emoji, user_id})

    def create_dm(user_id) do
      mock(
        :create_dm,
        {user_id},
        fn _ -> {:ok, DiscordFactory.channel(type: 1)} end
      )
    end

    defp mock(name, args, default_func \\ fn _ -> {:ok} end) do
      send(
        self(),
        {@mock, :called, name, args}
      )

      receive do
        {@mock, :mock, ^name, func} when is_function(func) ->
          apply(func, args |> Tuple.to_list())
      after
        0 -> default_func.(args)
      end
    end
  end

  def mock(name, func) when is_function(func) do
    send(self(), {@mock, :mock, name, func})
  end

  def pop do
    receive do
      {@mock, :called, func, data} -> {:ok, {func, data}}
    after
      0 -> {:error, :empty}
    end
  end

  def pop! do
    case pop() do
      {:ok, data} -> data
      {:error, :empty} -> raise "Empty Deploy queue"
    end
  end

  def assert_empty do
    case pop() do
      {:error, :empty} ->
        :ok

      {:ok, data} ->
        case flush() do
          0 -> raise "Unexpected data on queue: #{inspect(data)}"
          n -> raise "Unexpected data on queue: #{inspect(data)} (plus #{n} more)"
        end
    end
  end

  def flush(count \\ 0) do
    case pop() do
      {:error, :empty} -> count
      {:ok, _} -> flush(count + 1)
    end
  end

  def messages do
    case pop() do
      {:error, :empty} -> []
      {:ok, data} -> [data | messages()]
    end
  end
end
