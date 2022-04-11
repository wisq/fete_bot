defmodule FeteBot.Test.MockDiscord do
  defmodule Backend do
    alias FeteBot.Test.DiscordFactory
    alias FeteBot.Test.MockDiscord

    def create_message(channel_id, options) do
      call(
        :create_message,
        {channel_id, options},
        fn _ -> {:ok, DiscordFactory.build(:message, channel_id: channel_id)} end
      )
    end

    def edit_message(channel_id, message_id, options) do
      call(
        :edit_message,
        {channel_id, message_id, options},
        fn _ ->
          {:ok, DiscordFactory.build(:message, channel_id: channel_id, id: message_id)}
        end
      )
    end

    def delete_message(channel_id, message_id),
      do: call(:delete_message, {channel_id, message_id})

    def get_reactions(channel_id, message_id, emoji),
      do: call(:get_reactions, {channel_id, message_id, emoji}, fn _ -> {:ok, []} end)

    def create_reaction(channel_id, message_id, emoji),
      do: call(:create_reaction, {channel_id, message_id, emoji})

    def delete_reaction(channel_id, message_id, emoji),
      do: call(:delete_reaction, {channel_id, message_id, emoji})

    def delete_user_reaction(channel_id, message_id, emoji, user_id),
      do: call(:delete_user_reaction, {channel_id, message_id, emoji, user_id})

    def create_dm(user_id) do
      call(
        :create_dm,
        {user_id},
        fn _ -> {:ok, DiscordFactory.build(:channel, type: 1)} end
      )
    end

    defp call(name, args, default_func \\ fn _ -> {:ok} end) do
      case MockDiscord.calling(name, args) do
        {:fn, func} -> apply(func, args |> Tuple.to_list())
        :default -> default_func.(args)
      end
    end
  end

  defmodule PidState do
    defstruct(
      mocks: %{},
      messages: []
    )
  end

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def calling(name, args) do
    GenServer.call(__MODULE__, {:calling, self(), name, args})
  end

  def mock(name, func, pid \\ self()) when is_function(func) and is_pid(pid) do
    GenServer.cast(__MODULE__, {:mock, pid, name, func})
  end

  def messages(pid \\ self()) do
    GenServer.call(__MODULE__, {:messages, pid})
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:mock, pid, name, func}, state) do
    pst = Map.get(state, pid, %PidState{})
    {:noreply, Map.put(state, pid, add_mock(pst, name, func))}
  end

  defp add_mock(%PidState{} = pst, name, func) do
    queue =
      Map.get(pst.mocks, name, :queue.new())
      |> then(&:queue.in(func, &1))

    %PidState{pst | mocks: Map.put(pst.mocks, name, queue)}
  end

  defp pop_mock(%PidState{} = pst, name) do
    case Map.fetch(pst.mocks, name) do
      {:ok, queue} ->
        {mock, queue} = pop_mock_queue(queue)
        {mock, %PidState{pst | mocks: Map.put(pst.mocks, name, queue)}}

      :error ->
        {:default, pst}
    end
  end

  defp pop_mock_queue(queue) do
    case :queue.out(queue) do
      {{:value, mock}, q} -> {{:fn, mock}, q}
      {:empty, q} -> {:default, q}
    end
  end

  @impl true
  def handle_call({:messages, pid}, _from, state) do
    case Map.fetch(state, pid) do
      {:ok, pst} ->
        {
          :reply,
          pst.messages |> Enum.reverse(),
          Map.put(state, pid, %PidState{pst | messages: []})
        }

      :error ->
        {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:calling, pid, name, args}, _from, state) do
    pst = Map.get(state, pid, %PidState{})
    {mock, pst} = pop_mock(pst, name)

    message = {name, args}
    pst = %PidState{pst | messages: [message | pst.messages]}

    {:reply, mock, Map.put(state, pid, pst)}
  end
end
