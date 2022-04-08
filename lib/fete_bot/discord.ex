defmodule FeteBot.Discord do
  @config Application.get_env(:fete_bot, __MODULE__, [])
  @backend Keyword.get(@config, :backend, Nostrum.Api)
  require Logger

  def create_message(channel_id, options) do
    fn -> @backend.create_message(channel_id, options) end
    |> rate_limited("create_message/2")
  end

  def create_message!(channel_id, options) do
    create_message(channel_id, options)
    |> bangify
  end

  def edit_message(channel_id, message_id, options) do
    fn -> @backend.edit_message(channel_id, message_id, options) end
    |> rate_limited("edit_message/3")
  end

  def edit_message!(channel_id, message_id, options) do
    edit_message(channel_id, message_id, options)
    |> bangify
  end

  def delete_message(channel_id, message_id) do
    fn -> @backend.delete_message(channel_id, message_id) end
    |> rate_limited("delete_message/2")
  end

  def get_reactions(channel_id, message_id, emoji) do
    fn -> @backend.get_reactions(channel_id, message_id, emoji) end
    |> rate_limited("get_reactions/3")
  end

  def create_reaction(channel_id, message_id, emoji) do
    fn -> @backend.create_reaction(channel_id, message_id, emoji) end
    |> rate_limited("create_reaction/3")
  end

  def delete_reaction(channel_id, message_id, emoji) do
    fn -> @backend.delete_reaction(channel_id, message_id, emoji) end
    |> rate_limited("delete_reaction/3")
  end

  def delete_user_reaction(channel_id, message_id, emoji, user_id) do
    fn -> @backend.delete_user_reaction(channel_id, message_id, emoji, user_id) end
    |> rate_limited("delete_user_reaction/4")
  end

  def create_dm(user_id) do
    fn -> @backend.create_dm(user_id) end
    |> rate_limited("create_dm/1")
  end

  defp rate_limited(func, name) do
    1..4
    |> Enum.reduce_while(nil, fn n, _ ->
      rate_limited_attempt(n, func, name)
    end)
  end

  defp rate_limited_attempt(4, _, name) do
    raise "Got rate-limited too many times while trying to run #{name}"
  end

  defp rate_limited_attempt(_, func, name) do
    case func.() do
      {:error, %{status_code: 429, response: %{retry_after: secs}}} ->
        ms = ceil(secs * 1000) |> min(5000)
        Logger.warn("Got rate-limited on #{name}, sleeping for #{ms}ms")
        Process.sleep(ms)
        {:cont, nil}

      other ->
        {:halt, other}
    end
  end

  defp bangify(to_bang) do
    case to_bang do
      {:error, error} ->
        raise(error)

      {:ok, body} ->
        body

      {:ok} ->
        {:ok}
    end
  end
end
