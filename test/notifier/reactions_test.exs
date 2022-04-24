defmodule FeteBot.Notifier.ReactionsTest do
  use FeteBot.TestCase, async: true

  alias FeteBot.Test.{DataFactory, DiscordFactory, MockDiscord}
  alias FeteBot.Notifier.Reactions
  alias FeteBot.Notifier.Alarm
  alias Timex.Duration
  alias Ecto.Changeset

  ExUnit.Case.register_attribute(__MODULE__, :channel)

  # Summary reactions:
  @emoji_number "\uFE0F\u20E3"
  @emoji_1 "1#{@emoji_number}"
  @emoji_2 "2#{@emoji_number}"
  @emoji_3 "3#{@emoji_number}"
  @emoji_alarm_clock "\u{23F0}"
  @emoji_x "\u{274C}"

  # Editing reactions:
  @emoji_back_large "\u{23EE}\u{FE0F}"
  @emoji_back_small "\u{23EA}"
  @emoji_party "\u{1F389}"
  @emoji_fwd_small "\u{23E9}"
  @emoji_fwd_large "\u{23ED}\u{FE0F}"
  @emoji_checkmark "\u{2705}"

  # Just some random other emoji:
  @unknown_emoji [
    "\u{1F531}",
    "\u{2665}\u{FE0F}",
    "\u{1F45D}",
    "\u{1F31E}",
    "\u{1F38D}"
  ]

  describe "reacting to a summary message with alarm clock" do
    setup [
      :create_user,
      :with_alarm,
      :with_alarm,
      :with_summary_message,
      :alarm_clock_emoji,
      :reaction_add_event
    ]

    test "should add a new alarm", %{event: event, user: user} do
      assert [alarm1, alarm2] = Repo.preload(user, :alarms).alarms

      Reactions.on_reaction_add(event)

      assert [_, _, _] = alarms = Repo.preload(user, :alarms).alarms
      assert [new_alarm] = alarms |> List.delete(alarm1) |> List.delete(alarm2)
      assert new_alarm.event == :session
      assert new_alarm.margin == Duration.from_minutes(5)
    end

    test "should send a new summary message", %{event: event, user: user} do
      Reactions.on_reaction_add(event)

      assert [
               {:delete_message, {dm_id, old_summary_id}},
               {:create_message, {dm_id, "You have the following alarms:" <> text}},
               {:create_reaction, {dm_id, new_summary_id, @emoji_1}},
               {:create_reaction, {dm_id, new_summary_id, @emoji_2}},
               {:create_reaction, {dm_id, new_summary_id, @emoji_3}},
               {:create_reaction, {dm_id, new_summary_id, @emoji_alarm_clock}},
               {:create_reaction, {dm_id, new_summary_id, @emoji_x}}
             ] = MockDiscord.messages()

      assert text =~ "\n#{@emoji_1} —"
      assert text =~ "\n#{@emoji_2} —"
      assert text =~ "\n#{@emoji_3} —"
      assert text =~ "\n#{@emoji_alarm_clock} —"
      assert text =~ "\n#{@emoji_x} —"

      assert dm_id == user.dm_id
      assert old_summary_id == user.summary_message_id
      assert new_summary_id == Repo.reload(user).summary_message_id
    end
  end

  describe "reacting to a summary message with X" do
    setup [
      :create_user,
      :with_alarm,
      :with_alarm,
      :with_summary_message,
      :x_emoji,
      :reaction_add_event
    ]

    test "should delete all alarms", %{event: event, user: user} do
      assert [_, _] = Repo.preload(user, :alarms).alarms

      Reactions.on_reaction_add(event)

      assert [] = Repo.preload(user, :alarms).alarms
    end

    test "should send a new summary message", %{event: event, user: user} do
      Reactions.on_reaction_add(event)

      assert [
               {:delete_message, {dm_id, old_summary_id}},
               {:create_message, {dm_id, "You have no alarms" <> _}},
               {:create_reaction, {dm_id, new_summary_id, _}}
             ] = MockDiscord.messages() |> Enum.take(3)

      assert dm_id == user.dm_id
      assert old_summary_id == user.summary_message_id
      assert new_summary_id == Repo.reload(user).summary_message_id
    end
  end

  describe "reacting to a summary message with a number emoji" do
    setup [
      :create_user,
      :with_alarm,
      :with_alarm,
      :with_alarm,
      :with_summary_message,
      :pick_random_alarm,
      :alarm_number_emoji,
      :reaction_add_event
    ]

    test "should send a message to edit that alarm", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [
               {:create_message, {dm_id, text}},
               {:create_reaction, {dm_id, message_id, @emoji_back_large}},
               {:create_reaction, {dm_id, message_id, @emoji_back_small}},
               {:create_reaction, {dm_id, message_id, @emoji_party}},
               {:create_reaction, {dm_id, message_id, @emoji_fwd_small}},
               {:create_reaction, {dm_id, message_id, @emoji_fwd_large}},
               {:create_reaction, {dm_id, message_id, @emoji_x}},
               {:create_reaction, {dm_id, message_id, @emoji_checkmark}}
             ] = MockDiscord.messages()

      assert text =~ "Use the reactions below to edit this alarm:"
      assert text =~ "#{alarm.alarm_number}#{@emoji_number}"

      assert dm_id == user.dm_id
      assert Repo.reload!(alarm).editing_message_id == message_id
    end

    test "should delete an existing edit message for that alarm", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      old_message_id = DiscordFactory.generate_snowflake()
      Changeset.change(alarm, editing_message_id: old_message_id) |> Repo.update!()

      Reactions.on_reaction_add(event)

      assert [
               {:delete_message, {dm_id, ^old_message_id}},
               {:create_message, {dm_id, _}},
               {:create_reaction, {dm_id, new_message_id, @emoji_back_large}}
             ] = MockDiscord.messages() |> Enum.take(3)

      assert dm_id == user.dm_id
      assert Repo.reload!(alarm).editing_message_id == new_message_id
    end
  end

  describe "reacting to a summary message with an unknown emoji" do
    setup [
      :create_user,
      :with_alarm,
      :with_summary_message,
      :unknown_emoji,
      :reaction_add_event
    ]

    test "should do nothing", %{event: event, user: user} do
      assert [alarm] = Repo.preload(user, :alarms).alarms

      Reactions.on_reaction_add(event)

      assert [] = MockDiscord.messages()
      assert user == Repo.reload(user)
      assert [^alarm] = Repo.preload(user, :alarms).alarms
    end
  end

  describe "reacting to an alarm editing message with X" do
    setup [
      :create_user,
      :with_alarm,
      :with_alarm,
      :with_alarm,
      :with_summary_message,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :x_emoji,
      :reaction_add_event
    ]

    test "should delete the chosen alarm", %{event: event, user: user, alarm: alarm} do
      assert [_, _, _] = Repo.preload(user, :alarms).alarms

      Reactions.on_reaction_add(event)

      assert [_, _] = Repo.preload(user, :alarms).alarms
      assert Repo.reload(alarm) == nil
    end

    test "should delete the editing message and send a new summary message", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [
               {:delete_message, {dm_id, old_editing_id}},
               {:delete_message, {dm_id, old_summary_id}},
               {:create_message, {dm_id, _}},
               {:create_reaction, {dm_id, new_summary_id, _}}
             ] = MockDiscord.messages() |> Enum.take(4)

      assert dm_id == user.dm_id
      assert old_editing_id == alarm.editing_message_id
      assert old_summary_id == user.summary_message_id
      assert new_summary_id == Repo.reload(user).summary_message_id
    end
  end

  describe "reacting to an alarm editing message with checkmark" do
    setup [
      :create_user,
      :with_alarm,
      :with_alarm,
      :with_alarm,
      :with_summary_message,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :checkmark_emoji,
      :reaction_add_event
    ]

    test "should not touch alarms", %{event: event, user: user} do
      assert [_, _, _] = old_alarms = Repo.preload(user, :alarms).alarms

      Reactions.on_reaction_add(event)

      assert [_, _, _] = ^old_alarms = Repo.preload(user, :alarms).alarms
    end

    test "should delete the editing message and send a new summary message", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [
               {:delete_message, {dm_id, old_editing_id}},
               {:delete_message, {dm_id, old_summary_id}},
               {:create_message, {dm_id, _}},
               {:create_reaction, {dm_id, new_summary_id, _}}
             ] = MockDiscord.messages() |> Enum.take(4)

      assert dm_id == user.dm_id
      assert old_editing_id == alarm.editing_message_id
      assert old_summary_id == user.summary_message_id
      assert new_summary_id == Repo.reload(user).summary_message_id
    end
  end

  describe "reacting to an alarm editing message with 'large backwards' emoji" do
    setup [
      :create_user,
      :with_alarm,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :back_large_emoji,
      :reaction_add_event
    ]

    test "should increase margin by 5 minutes", %{event: event, alarm: alarm} do
      old_margin = alarm.margin |> Duration.to_minutes()
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()
      assert new_margin == old_margin + 5
    end

    test "should limit margin to 90 minutes for session alarms", %{event: event, alarm: alarm} do
      alarm =
        alarm
        |> update_alarm_type(:session)
        |> update_alarm_margin(86..89)
        |> Repo.update!()

      old_margin = alarm.margin |> Duration.to_minutes()
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()
      assert new_margin != old_margin
      assert new_margin == 90
    end

    test "should limit margin to 180 minutes for epoch alarms", %{event: event, alarm: alarm} do
      alarm =
        alarm
        |> update_alarm_type(:epoch)
        |> update_alarm_margin(176..179)
        |> Repo.update!()

      old_margin = alarm.margin |> Duration.to_minutes()
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()
      assert new_margin != old_margin
      assert new_margin == 180
    end

    test "should edit the editing message", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [{:edit_message, {dm_id, editing_id, _}}] = MockDiscord.messages()

      assert dm_id == user.dm_id
      assert editing_id == alarm.editing_message_id
    end
  end

  describe "reacting to an alarm editing message with 'small backwards' emoji" do
    setup [
      :create_user,
      :with_alarm,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :back_small_emoji,
      :reaction_add_event
    ]

    test "should increase margin by 1 minute", %{event: event, alarm: alarm} do
      old_margin = alarm.margin |> Duration.to_minutes()
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()
      assert new_margin == old_margin + 1
    end

    test "should limit margin to 90 minutes for session alarms", %{event: event, alarm: alarm} do
      alarm =
        alarm
        |> update_alarm_type(:session)
        |> update_alarm_margin(89)
        |> Repo.update!()

      old_margin = alarm.margin |> Duration.to_minutes()

      # Increase to 90:
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()

      # Fail to increase further:
      Reactions.on_reaction_add(event)
      ^new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()

      assert new_margin != old_margin
      assert new_margin == 90
    end

    test "should limit margin to 180 minutes for epoch alarms", %{event: event, alarm: alarm} do
      alarm =
        alarm
        |> update_alarm_type(:epoch)
        |> update_alarm_margin(179)
        |> Repo.update!()

      old_margin = alarm.margin |> Duration.to_minutes()

      # Increase to 180:
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()

      # Fail to increase further:
      Reactions.on_reaction_add(event)
      ^new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()

      assert new_margin != old_margin
      assert new_margin == 180
    end

    test "should edit the editing message", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [{:edit_message, {dm_id, editing_id, _}}] = MockDiscord.messages()

      assert dm_id == user.dm_id
      assert editing_id == alarm.editing_message_id
    end
  end

  describe "reacting to an alarm editing message with 'small forwards' emoji" do
    setup [
      :create_user,
      :with_alarm,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :fwd_small_emoji,
      :reaction_add_event
    ]

    test "should decrease margin by 1 minute", %{event: event, alarm: alarm} do
      old_margin = alarm.margin |> Duration.to_minutes()
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()
      assert new_margin == old_margin - 1
    end

    test "should limit margin to 0 minutes", %{event: event, alarm: alarm} do
      alarm =
        alarm
        |> update_alarm_margin(1)
        |> Repo.update!()

      old_margin = alarm.margin |> Duration.to_minutes()

      # Decrease to 0:
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()

      # Fail to decrease further:
      Reactions.on_reaction_add(event)
      ^new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()

      assert new_margin != old_margin
      assert new_margin == 0
    end

    test "should edit the editing message", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [{:edit_message, {dm_id, editing_id, _}}] = MockDiscord.messages()

      assert dm_id == user.dm_id
      assert editing_id == alarm.editing_message_id
    end
  end

  describe "reacting to an alarm editing message with 'large forwards' emoji" do
    setup [
      :create_user,
      :with_alarm,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :fwd_large_emoji,
      :reaction_add_event
    ]

    test "should decrease margin by 5 minutes", %{event: event, alarm: alarm} do
      old_margin = alarm.margin |> Duration.to_minutes()
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()
      assert new_margin == old_margin - 5
    end

    test "should limit margin to 0 minutes", %{event: event, alarm: alarm} do
      alarm =
        alarm
        |> update_alarm_margin(1..4)
        |> Repo.update!()

      old_margin = alarm.margin |> Duration.to_minutes()
      Reactions.on_reaction_add(event)
      new_margin = Repo.reload!(alarm).margin |> Duration.to_minutes()

      assert new_margin != old_margin
      assert new_margin == 0
    end

    test "should edit the editing message", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [{:edit_message, {dm_id, editing_id, _}}] = MockDiscord.messages()

      assert dm_id == user.dm_id
      assert editing_id == alarm.editing_message_id
    end
  end

  describe "reacting to an alarm editing message with party emoji" do
    setup [
      :create_user,
      :with_alarm,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :party_emoji,
      :reaction_add_event
    ]

    test "should toggle alarm event type", %{event: event, alarm: alarm} do
      old_event = alarm.event
      Reactions.on_reaction_add(event)
      new_event = Repo.reload!(alarm).event

      case old_event do
        :epoch -> assert new_event == :session
        :session -> assert new_event == :epoch
      end
    end

    test "should limit margin to 90 minutes when switching to session alarms", %{
      event: event,
      alarm: alarm
    } do
      alarm =
        alarm
        |> update_alarm_type(:epoch)
        |> update_alarm_margin(91..180)
        |> Repo.update!()

      Reactions.on_reaction_add(event)
      assert Repo.reload!(alarm).margin |> Duration.to_minutes() == 90
    end

    test "should edit the editing message", %{
      event: event,
      user: user,
      alarm: alarm
    } do
      Reactions.on_reaction_add(event)

      assert [{:edit_message, {dm_id, editing_id, _}}] = MockDiscord.messages()

      assert dm_id == user.dm_id
      assert editing_id == alarm.editing_message_id
    end
  end

  describe "reacting to an alarm editing message with an unknown emoji" do
    setup [
      :create_user,
      :with_alarm,
      :pick_random_alarm,
      :with_alarm_editing_message,
      :unknown_emoji,
      :reaction_add_event
    ]

    test "should do nothing", %{event: event, user: user} do
      assert [alarm] = Repo.preload(user, :alarms).alarms

      Reactions.on_reaction_add(event)

      assert [] = MockDiscord.messages()
      assert user == Repo.reload(user)
      assert [^alarm] = Repo.preload(user, :alarms).alarms
    end
  end

  defp create_user(_context) do
    user = DataFactory.insert!(:alarm_user)
    [user: user]
  end

  defp with_alarm(%{user: user} = context) do
    alarms = Map.get(context, :alarms, [])

    max_number =
      alarms
      |> Enum.map(& &1.alarm_number)
      |> Enum.max(fn -> 0 end)

    alarm =
      DataFactory.insert!(:alarm,
        alarm_user_id: user.id,
        alarm_number: max_number + 1,
        event: [:epoch, :session] |> Enum.random(),
        margin: 10..30 |> Enum.random() |> Duration.from_minutes()
      )

    [alarms: [alarm | alarms]]
  end

  defp pick_random_alarm(%{alarms: alarms}), do: [alarm: Enum.random(alarms)]

  defp with_summary_message(%{user: user}) do
    user =
      Changeset.change(user,
        dm_id: DiscordFactory.generate_snowflake(),
        summary_message_id: DiscordFactory.generate_snowflake()
      )
      |> Repo.update!()

    [user: user, channel_id: user.dm_id, message_id: user.summary_message_id]
  end

  defp with_alarm_editing_message(%{user: user, alarm: alarm}) do
    alarm =
      Changeset.change(alarm,
        editing_message_id: DiscordFactory.generate_snowflake()
      )
      |> Repo.update!()

    [alarm: alarm, channel_id: user.dm_id, message_id: alarm.editing_message_id]
  end

  defp update_alarm_type(alarm, type), do: Changeset.change(alarm, event: type)

  defp update_alarm_margin(alarm, mins) when is_integer(mins),
    do: update_alarm_margin(alarm, mins..mins)

  defp update_alarm_margin(alarm, _.._ = range) do
    Changeset.change(alarm, margin: range |> Enum.random() |> Duration.from_minutes())
  end

  defp alarm_clock_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_alarm_clock)]
  defp x_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_x)]
  defp checkmark_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_checkmark)]
  defp back_large_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_back_large)]
  defp back_small_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_back_small)]
  defp party_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_party)]
  defp fwd_small_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_fwd_small)]
  defp fwd_large_emoji(_), do: [emoji: DiscordFactory.build(:emoji, name: @emoji_fwd_large)]

  defp alarm_number_emoji(%{alarm: %Alarm{alarm_number: n}}) do
    [emoji: DiscordFactory.build(:emoji, name: "#{n}#{@emoji_number}")]
  end

  defp unknown_emoji(_context) do
    [emoji: DiscordFactory.build(:emoji, name: Enum.random(@unknown_emoji))]
  end

  defp reaction_add_event(%{channel_id: c_id, message_id: m_id, user: user, emoji: emoji}) do
    [
      event:
        DiscordFactory.build(:message_reaction_add_event,
          channel_id: c_id,
          message_id: m_id,
          user_id: user.user_id,
          emoji: emoji
        )
    ]
  end
end
