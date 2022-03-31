defmodule FeteBot.Notifier.Reactions do
  require Logger
  alias Nostrum.Api, as: Discord
  alias Nostrum.Struct.{Message, Emoji}

  alias FeteBot.Notifier
  alias FeteBot.Notifier.Alarm

  @summary_alarm_commands 1..9 |> Map.new(fn n -> {Alarm.number_emoji(n), {:edit, n}} end)
  @summary_commands %{
    "\u{23F0}" => :add,
    "\u{274C}" => :delete_all
  }
  @all_summary_commands Map.merge(@summary_commands, @summary_alarm_commands)

  def on_reaction_add(event) do
    emoji = Emoji.api_name(event.emoji)

    cond do
      handle_summary_command(emoji, event) -> :ok
      true -> :noop
    end
  end

  def on_reaction_remove(event) do
    IO.inspect(event)
  end

  defp handle_summary_command(emoji, ev) do
    with {:ok, command} <- Map.fetch(@all_summary_commands, emoji),
         {:ok, user} <- Notifier.find_user_by_summary_message(ev.channel_id, ev.message_id) do
      on_summary_command(command, user, ev)
      true
    else
      :error -> false
    end
  end

  def add_summary_reactions(%Message{} = msg, alarms) when is_list(alarms) do
    alarms
    |> Enum.map(&Alarm.number_emoji/1)
    |> Enum.sort()
    |> add_summary_command_emoji()
    |> Enum.each(fn emoji ->
      add_reaction(msg, emoji)
    end)
  end

  defp add_summary_command_emoji(list) do
    if Enum.count(list) >= Alarm.max_per_user() do
      @summary_commands
      |> Map.reject(fn {_, cmd} -> cmd == :add end)
    else
      @summary_commands
    end
    |> Map.keys()
    |> then(&Enum.concat(list, &1))
  end

  defp add_reaction(%Message{} = msg, emoji) do
    case Discord.create_reaction(msg.channel_id, msg.id, emoji) do
      {:ok} ->
        :ok

      {:error, %{status_code: 429, response: %{retry_after: secs}}} when secs < 5.0 ->
        ms = ceil(secs * 1000)
        Logger.warn("Rate-limited adding reactions, sleeping for #{ms}ms")
        Process.sleep(ms)
        add_reaction(msg, emoji)
    end
  end

  defp on_summary_command(:add, user, _event) do
    Notifier.create_alarm(user)
  end

  defp on_summary_command(:delete_all, user, _event) do
    Notifier.delete_all_alarms(user)
  end

  defp on_summary_command(cmd, user, event) do
    IO.inspect({cmd, user, event})
  end
end
