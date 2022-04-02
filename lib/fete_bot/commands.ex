defmodule FeteBot.Commands do
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Struct.Message

  alias FeteBot.Tracker
  alias FeteBot.Discord

  @bot "FêteBot"

  def run("enable", msg) do
    with :ok <- check_guild_owner(msg.author.id, msg.guild_id),
         :ok <- Tracker.enable(msg.channel_id) do
      reply(msg, "#{@bot} has been enabled in #{channel_link(msg)}.")
    else
      {:error, :not_owner} ->
        reply(msg, "This command can only be run by the server owner.")

      {:error, :already_enabled} ->
        reply(msg, "#{@bot} is already enabled in #{channel_link(msg)}.")
    end
  end

  def run("disable", msg) do
    with :ok <- check_guild_owner(msg.author.id, msg.guild_id),
         :ok <- Tracker.disable(msg.channel_id) do
      reply(msg, "#{@bot} has been disabled in #{channel_link(msg)}.")
    else
      {:error, :not_owner} ->
        reply(msg, "This command can only be run by the server owner.")

      {:error, :not_enabled} ->
        reply(msg, "#{@bot} is not enabled in #{channel_link(msg)}.")
    end
  end

  def run(_, msg) do
    reply(msg, "I don't understand that command.")
  end

  defp check_guild_owner(user_id, guild_id) do
    {:ok, guild} = guild_id |> GuildCache.get()

    case guild.owner_id == user_id do
      true -> :ok
      false -> {:error, :not_owner}
    end
  end

  defp reply(msg, text) do
    Discord.create_message(
      msg.channel_id,
      content: text,
      message_reference: %{message_id: msg.id}
    )
  end

  defp channel_link(%Message{channel_id: cid}), do: channel_link(cid)
  defp channel_link(id) when is_integer(id), do: "<##{id}>"
end
