defmodule FeteBot.Tracker.ReactionsTest do
  use FeteBot.TestCase, async: true

  alias FeteBot.Test.{DataFactory, DiscordFactory, MockDiscord}
  alias FeteBot.Tracker.Reactions
  alias FeteBot.Notifier.AlarmUser

  ExUnit.Case.register_attribute(__MODULE__, :channel)

  describe "reacting to a tracker message with alarm clock as a new user" do
    setup [:create_channel, :new_user, :alarm_clock_emoji, :reaction_add_event]

    test "should set a default alarm", %{event: event} do
      Reactions.on_reaction_add(event)

      # Check that user was created:
      assert user = Repo.get_by(AlarmUser, user_id: event.user_id)
      # Check that alarm was created:
      assert [alarm] = Repo.preload(user, :alarms).alarms
      assert alarm.alarm_number == 1
      assert alarm.event == :session
      assert alarm.margin == Timex.Duration.from_minutes(5)
    end

    test "should send an alarm summary message to user via DM", %{event: event} do
      assert user_id = event.user_id

      Reactions.on_reaction_add(event)

      # Check that user was notified:
      assert [
               {:create_dm, {^user_id}},
               {:create_message, {dm_id, "You have the following alarms:" <> summary}},
               {:create_reaction, {dm_id, message_id, _}}
             ] = MockDiscord.messages() |> Enum.take(3)

      # Check that values were stored to database:
      assert user = Repo.get_by(AlarmUser, user_id: user_id)
      assert user.dm_id == dm_id
      assert user.summary_message_id == message_id
      assert summary =~ "**five minutes** before **each fête**"
    end

    test "should delete the user's alarm clock reaction", %{event: event} do
      assert channel_id = event.channel_id
      assert message_id = event.message_id
      assert emoji = event.emoji
      assert user_id = event.user_id

      Reactions.on_reaction_add(event)

      assert {:delete_user_reaction, {^channel_id, ^message_id, ^emoji, ^user_id}} =
               MockDiscord.messages() |> List.last()
    end
  end

  describe "reacting to a tracker message with alarm clock as a user with existing alarms" do
    setup [:create_channel, :create_user, :create_alarms, :alarm_clock_emoji, :reaction_add_event]

    test "should send an alarm summary message to user via DM", %{event: event} do
      Reactions.on_reaction_add(event)

      # Check that user was notified:
      assert [
               {:create_dm, _},
               {:create_message, {_, "You have the following alarms:" <> summary}}
             ] = MockDiscord.messages() |> Enum.take(2)

      assert summary =~ "**ten minutes** before **each fête**"
      assert summary =~ "**three minutes** before **each fête**"
      assert summary =~ "**90 minutes** before the **next series**"
    end

    test "should not create any additional alarms", %{event: event, alarm_user: user} do
      alarms = Repo.preload(user, :alarms).alarms
      Reactions.on_reaction_add(event)
      assert alarms == Repo.preload(user, :alarms, force: true).alarms
    end
  end

  describe "reacting to a tracker message with an unknown emoji" do
    setup [:create_channel, :new_user, :unknown_emoji, :reaction_add_event]

    test "should do nothing", %{event: event} do
      Reactions.on_reaction_add(event)
      assert [] = MockDiscord.messages()
      assert [] = Repo.all(AlarmUser)
    end
  end

  describe "reacting to a non-tracker message with an alarm clock emoji" do
    setup [:unknown_channel, :new_user, :alarm_clock_emoji, :reaction_add_event]

    test "should do nothing", %{event: event} do
      Reactions.on_reaction_add(event)
      assert [] = MockDiscord.messages()
      assert [] = Repo.all(AlarmUser)
    end
  end

  describe "reacting to a non-tracker message with an unknown emoji" do
    setup [:unknown_channel, :new_user, :unknown_emoji, :reaction_add_event]

    test "should do nothing", %{event: event} do
      Reactions.on_reaction_add(event)
      assert [] = MockDiscord.messages()
      assert [] = Repo.all(AlarmUser)
    end
  end

  defp create_channel(_context) do
    channel = DataFactory.insert!(:channel, message_id: DiscordFactory.generate_snowflake())
    [channel: channel, channel_id: channel.channel_id, message_id: channel.message_id]
  end

  defp unknown_channel(_context) do
    message = DiscordFactory.build(:message)
    [channel_id: message.channel_id, message_id: message.id]
  end

  def new_user(_context), do: [user_id: DiscordFactory.generate_snowflake()]

  defp create_user(_context) do
    user = DataFactory.insert!(:alarm_user)
    [alarm_user: user, user_id: user.user_id]
  end

  defp create_alarms(%{alarm_user: user}) do
    alarm1 =
      DataFactory.insert!(:alarm,
        alarm_user_id: user.id,
        alarm_number: 1,
        event: :session,
        margin: Timex.Duration.from_minutes(10)
      )

    alarm2 =
      DataFactory.insert!(:alarm,
        alarm_user_id: user.id,
        alarm_number: 2,
        event: :session,
        margin: Timex.Duration.from_minutes(3)
      )

    alarm3 =
      DataFactory.insert!(:alarm,
        alarm_user_id: user.id,
        alarm_number: 3,
        event: :epoch,
        margin: Timex.Duration.from_minutes(90)
      )

    [alarms: [alarm1, alarm2, alarm3]]
  end

  defp alarm_clock_emoji(_context) do
    [emoji: DiscordFactory.build(:emoji, name: "\u{23F0}")]
  end

  @unknown_emoji [
    "\u{23EE}\u{FE0F}",
    "\u{23EA}",
    "\u{1F389}",
    "\u{23E9}",
    "\u{23ED}\u{FE0F}"
  ]

  defp unknown_emoji(_context) do
    [emoji: DiscordFactory.build(:emoji, name: Enum.random(@unknown_emoji))]
  end

  defp reaction_add_event(%{channel_id: c_id, message_id: m_id, user_id: u_id, emoji: emoji}) do
    [
      event:
        DiscordFactory.build(:message_reaction_add_event,
          channel_id: c_id,
          message_id: m_id,
          user_id: u_id,
          emoji: emoji
        )
    ]
  end
end
