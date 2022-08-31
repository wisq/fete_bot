defmodule FeteBot.Commands do
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Struct.Message

  alias FeteBot.Tracker
  alias FeteBot.Discord

  @bot "FêteBot"
  @not_manager_msg "This command can only be run by the server owner, or by users with the \"Manage Server\" permission."

  def run("enable", msg) do
    with :ok <- check_guild_manager(msg.guild_id, msg.author.id, msg.member),
         :ok <- Tracker.enable(msg.channel_id) do
      reply(msg, "#{@bot} has been enabled in #{channel_link(msg)}.")
    else
      {:error, :not_manager} ->
        reply(msg, @not_manager_msg)

      {:error, :already_enabled} ->
        reply(msg, "#{@bot} is already enabled in #{channel_link(msg)}.")
    end
  end

  def run("disable", msg) do
    with :ok <- check_guild_manager(msg.guild_id, msg.author.id, msg.member),
         :ok <- Tracker.disable(msg.channel_id) do
      reply(msg, "#{@bot} has been disabled in #{channel_link(msg)}.")
    else
      {:error, :not_manager} ->
        reply(msg, @not_manager_msg)

      {:error, :not_enabled} ->
        reply(msg, "#{@bot} is not enabled in #{channel_link(msg)}.")
    end
  end

  def run(_, msg) do
    reply(msg, "I don't understand that command.")
  end

  defp check_guild_manager(guild_id, user_id, member) do
    {:ok, guild} = guild_id |> GuildCache.get()

    cond do
      user_id == guild.owner_id -> :ok
      :manage_guild in Nostrum.Struct.Guild.Member.guild_permissions(member, guild) -> :ok
      true -> {:error, :not_manager}
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
