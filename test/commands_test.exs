defmodule FeteBot.CommandsTest do
  use FeteBot.TestCase, async: true

  defmodule FakeScheduler do
    use GenServer
    @name FeteBot.Tracker.Scheduler

    def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: @name)
    def init(_), do: {:ok, nil}
    def handle_cast({:manual, channel}, _), do: {:noreply, channel}
    def handle_call(:get, _from, state), do: {:reply, state, state}

    def get, do: GenServer.call(@name, :get)
  end

  alias Nostrum.Cache.GuildCache.ETS, as: GuildCache
  alias FeteBot.Test.{DiscordFactory, DataFactory}
  alias FeteBot.Test.MockDiscord

  alias FeteBot.Commands
  alias FeteBot.Tracker.Channel

  @manage_guild_bit Nostrum.Permission.to_bit(:manage_guild)
  @not_manager_msg "This command can only be run by the server owner, or by users with the \"Manage Server\" permission."

  describe "run/2 with 'enable' command" do
    test "accepts command, creates a Channel record, and schedules a manual update" do
      owner = DiscordFactory.build(:user)
      guild = DiscordFactory.build(:guild, owner_id: owner.id)
      message = DiscordFactory.build(:message, author: owner, guild_id: guild.id)

      start_supervised!(GuildCache)
      GuildCache.create(guild)

      start_supervised!(FakeScheduler)
      Commands.run("enable", message)

      # Creates a record:
      assert row = Repo.get_by(Channel, channel_id: message.channel_id)
      # No tracker message yet.
      assert row.message_id == nil

      # Schedules a manual update:
      assert row == FakeScheduler.get()

      # Replies to message:
      assert [{:create_message, {cid, args}}] = MockDiscord.messages()
      assert cid == message.channel_id
      assert Keyword.get(args, :content) == "FêteBot has been enabled in <##{cid}>."
      assert Keyword.get(args, :message_reference).message_id == message.id
    end

    test "accepts command from server manager" do
      author = DiscordFactory.build(:user)
      owner = DiscordFactory.build(:user)
      role = DiscordFactory.build(:role, permissions: @manage_guild_bit)
      guild = DiscordFactory.build(:guild, owner_id: owner.id, roles: %{role.id => role})

      start_supervised!(GuildCache)
      GuildCache.create(guild)

      message =
        DiscordFactory.build(:message,
          author: author,
          guild_id: guild.id,
          member: DiscordFactory.build(:member, roles: [role.id])
        )

      start_supervised!(FakeScheduler)
      Commands.run("enable", message)

      # Replies to message:
      assert [{:create_message, {cid, args}}] = MockDiscord.messages()
      assert Keyword.get(args, :content) == "FêteBot has been enabled in <##{cid}>."
    end

    test "rejects command if user is regular user" do
      author = DiscordFactory.build(:user)
      owner = DiscordFactory.build(:user)

      # Dummy role, to make sure member role lookup is working correctly.
      role = DiscordFactory.build(:role, permissions: @manage_guild_bit)
      guild = DiscordFactory.build(:guild, owner_id: owner.id, roles: %{role.id => role})

      message = DiscordFactory.build(:message, author: author, guild_id: guild.id)

      start_supervised!(GuildCache)
      GuildCache.create(guild)

      start_supervised!(FakeScheduler)
      Commands.run("enable", message)

      # No record created:
      assert nil == Repo.get_by(Channel, channel_id: message.channel_id)

      # No update scheduled:
      assert nil == FakeScheduler.get()

      # Replies to message:
      assert [{:create_message, {cid, args}}] = MockDiscord.messages()
      assert cid == message.channel_id
      assert Keyword.get(args, :content) == @not_manager_msg
      assert Keyword.get(args, :message_reference).message_id == message.id
    end
  end

  describe "run/2 with 'disable' command" do
    test "accepts command from server owner and deletes the corresponding Channel record" do
      channel = DataFactory.insert!(:channel)
      owner = DiscordFactory.build(:user)
      guild = DiscordFactory.build(:guild, owner_id: owner.id)

      start_supervised!(GuildCache)
      GuildCache.create(guild)

      message =
        DiscordFactory.build(:message,
          author: owner,
          guild_id: guild.id,
          channel_id: channel.channel_id
        )

      Commands.run("disable", message)

      # Deletes row:
      assert nil == Repo.reload(channel)

      # Replies to message:
      assert [{:create_message, {cid, args}}] = MockDiscord.messages()
      assert cid == channel.channel_id
      assert Keyword.get(args, :content) == "FêteBot has been disabled in <##{cid}>."
      assert Keyword.get(args, :message_reference).message_id == message.id
    end

    test "accepts command from server manager" do
      channel = DataFactory.insert!(:channel)
      author = DiscordFactory.build(:user)
      owner = DiscordFactory.build(:user)
      role = DiscordFactory.build(:role, permissions: @manage_guild_bit)
      guild = DiscordFactory.build(:guild, owner_id: owner.id, roles: %{role.id => role})

      start_supervised!(GuildCache)
      GuildCache.create(guild)

      message =
        DiscordFactory.build(:message,
          author: author,
          guild_id: guild.id,
          channel_id: channel.channel_id,
          member: DiscordFactory.build(:member, roles: [role.id])
        )

      Commands.run("disable", message)

      # Replies to message:
      assert [{:create_message, {cid, args}}] = MockDiscord.messages()
      assert Keyword.get(args, :content) == "FêteBot has been disabled in <##{cid}>."
    end

    test "rejects command if user is regular user" do
      channel = DataFactory.insert!(:channel)
      author = DiscordFactory.build(:user)
      owner = DiscordFactory.build(:user)

      # Dummy role, to make sure member role lookup is working correctly.
      role = DiscordFactory.build(:role, permissions: @manage_guild_bit)
      guild = DiscordFactory.build(:guild, owner_id: owner.id, roles: %{role.id => role})

      message =
        DiscordFactory.build(:message,
          author: author,
          guild_id: guild.id,
          channel_id: channel.channel_id
        )

      start_supervised!(GuildCache)
      GuildCache.create(guild)

      Commands.run("disable", message)

      # Record unchanged:
      assert channel == Repo.get_by(Channel, channel_id: message.channel_id)

      # Replies to message:
      assert [{:create_message, {cid, args}}] = MockDiscord.messages()
      assert cid == message.channel_id
      assert Keyword.get(args, :content) == @not_manager_msg
      assert Keyword.get(args, :message_reference).message_id == message.id
    end

    test "handles channel not found" do
      existing_channel = DataFactory.insert!(:channel)
      owner = DiscordFactory.build(:user)
      guild = DiscordFactory.build(:guild, owner_id: owner.id)

      start_supervised!(GuildCache)
      GuildCache.create(guild)

      message =
        DiscordFactory.build(:message,
          author: owner,
          guild_id: guild.id,
          channel_id: existing_channel.channel_id + 1
        )

      Commands.run("disable", message)

      # Record unchanged:
      assert existing_channel == Repo.reload(existing_channel)

      # Replies to message:
      assert [{:create_message, {cid, args}}] = MockDiscord.messages()
      assert cid == message.channel_id
      assert Keyword.get(args, :content) == "FêteBot is not enabled in <##{cid}>."
      assert Keyword.get(args, :message_reference).message_id == message.id
    end
  end
end
