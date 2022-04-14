defmodule FeteBot.Notifier.SchedulerTest do
  use FeteBot.TestCase, async: true

  alias Timex.Duration
  alias FeteBot.Notifier.Scheduler
  alias FeteBot.Test.{MockDateTime, MockGenServer, MockDiscord}
  alias FeteBot.Test.{DataFactory, DiscordFactory}
  alias FeteBot.Fetes.Event

  @emoji_1 "1\uFE0F\u20E3"
  @emoji_2 "2\uFE0F\u20E3"
  @emoji_3 "3\uFE0F\u20E3"
  @emoji_x "\u{274C}"

  defp start_scheduler(start_time) do
    :ok = MockDateTime.mock_time(start_time)
    {:ok, pid} = MockGenServer.child_spec(Scheduler) |> start_supervised()
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    pid
  end

  defp alarm!(user, num, type, mins, other \\ []) do
    DataFactory.insert!(
      :alarm,
      [
        alarm_user_id: user.id,
        alarm_number: num,
        event: type,
        margin: Duration.from_minutes(mins)
      ]
      |> Keyword.merge(other)
    )
  end

  test "notifier scheduler sends epoch and session alarms for session #1" do
    user1 = DataFactory.insert!(:alarm_user)
    user2 = DataFactory.insert!(:alarm_user)
    alarm1 = alarm!(user1, 1, :epoch, 25)
    alarm2 = alarm!(user2, 1, :session, 10)

    pid = start_scheduler(~U[2022-04-15 14:30:00Z])
    calendar() |> Enum.at(0) |> Scheduler.next_event(pid)

    # First alarm is at 14:35
    MockDateTime.advance_to(~U[2022-04-15 14:34:59Z])
    assert [] = MockDiscord.messages(pid)
    MockDateTime.advance_to(~U[2022-04-15 14:35:01Z])

    assert [
             {:create_message,
              {user1_dm_id, "The next series of fêtes will start in 25 minutes."}},
             {:edit_message,
              {user1_dm_id, alarm1_msg_id,
               "The **next series** of fêtes will start at <t:1650034800:t> (<t:1650034800:R>)."}},
             {:create_reaction, {user1_dm_id, alarm1_msg_id, @emoji_1}},
             {:create_reaction, {user1_dm_id, alarm1_msg_id, @emoji_x}}
           ] = MockDiscord.messages(pid)

    assert user1_dm_id == user1.dm_id
    assert alarm1_msg_id == Repo.reload!(alarm1).last_alarm_message_id

    # Second alarm is at 14:50
    MockDateTime.advance_to(~U[2022-04-15 14:49:59Z])
    assert [] = MockDiscord.messages(pid)
    MockDateTime.advance_to(~U[2022-04-15 14:50:01Z])

    assert [
             {:create_message, {user2_dm_id, "The next fête will start in ten minutes."}},
             {:edit_message,
              {user2_dm_id, alarm2_msg_id,
               "The **next fête** will start at <t:1650034800:t> (<t:1650034800:R>)."}},
             {:create_reaction, {user2_dm_id, alarm2_msg_id, @emoji_1}},
             {:create_reaction, {user2_dm_id, alarm2_msg_id, @emoji_x}}
           ] = MockDiscord.messages(pid)

    assert user2_dm_id == user2.dm_id
    assert alarm2_msg_id == Repo.reload!(alarm2).last_alarm_message_id
  end

  test "notifier scheduler sends only session alarms for later sessions" do
    user = DataFactory.insert!(:alarm_user)
    alarm1 = alarm!(user, 1, :epoch, 25)
    alarm2 = alarm!(user, 2, :session, 10)

    pid = start_scheduler(~U[2022-04-15 15:30:00Z])
    calendar() |> Enum.at(1) |> Scheduler.next_event(pid)

    # alarm1 does not trigger
    MockDateTime.advance_to(~U[2022-04-15 16:49:59Z])
    assert [] = MockDiscord.messages(pid)
    assert nil == Repo.reload!(alarm1).last_alarm_message_id

    # alarm2 is at 16:50
    MockDateTime.advance_to(~U[2022-04-15 16:50:01Z])

    assert [
             {:create_message, {user_dm_id, "The next fête will start in ten minutes."}},
             {:edit_message,
              {user_dm_id, alarm2_msg_id,
               "The **next fête** will start at <t:1650042000:t> (<t:1650042000:R>)."}},
             {:create_reaction, {user_dm_id, alarm2_msg_id, @emoji_2}},
             {:create_reaction, {user_dm_id, alarm2_msg_id, @emoji_x}}
           ] = MockDiscord.messages(pid)

    assert user_dm_id == user.dm_id
    assert alarm2_msg_id == Repo.reload!(alarm2).last_alarm_message_id
  end

  test "notifier scheduler deletes last alarm message if set" do
    user = DataFactory.insert!(:alarm_user)
    old_message_id = DiscordFactory.generate_snowflake()
    alarm = alarm!(user, 3, :session, 3, last_alarm_message_id: old_message_id)

    pid = start_scheduler(~U[2022-04-15 20:30:00Z])
    calendar() |> Enum.at(3) |> Scheduler.next_event(pid)

    # alarm is at 20:57
    MockDateTime.advance_to(~U[2022-04-15 20:56:59Z])
    assert [] = MockDiscord.messages(pid)
    MockDateTime.advance_to(~U[2022-04-15 20:57:01Z])

    assert [
             {:delete_message, {user_dm_id, ^old_message_id}},
             {:create_message, {user_dm_id, "The next fête will start in three minutes."}},
             {:edit_message,
              {user_dm_id, new_message_id,
               "The **next fête** will start at <t:1650056400:t> (<t:1650056400:R>)."}},
             {:create_reaction, {user_dm_id, new_message_id, @emoji_3}},
             {:create_reaction, {user_dm_id, new_message_id, @emoji_x}}
           ] = MockDiscord.messages(pid)

    assert user_dm_id == user.dm_id
    assert new_message_id == Repo.reload!(alarm).last_alarm_message_id
  end

  defp calendar do
    [
      %Event{
        start_time: ~U[2022-04-15 15:00:00Z],
        end_time: ~U[2022-04-15 15:27:25Z],
        epoch: 16,
        session: 1
      },
      %Event{
        start_time: ~U[2022-04-15 17:00:00Z],
        end_time: ~U[2022-04-15 17:27:25Z],
        epoch: 16,
        session: 2
      },
      %Event{
        start_time: ~U[2022-04-15 19:00:00Z],
        end_time: ~U[2022-04-15 19:27:25Z],
        epoch: 16,
        session: 3
      },
      %Event{
        start_time: ~U[2022-04-15 21:00:00Z],
        end_time: ~U[2022-04-15 21:27:25Z],
        epoch: 16,
        session: 4
      },
      %Event{
        start_time: ~U[2022-04-15 23:00:00Z],
        end_time: ~U[2022-04-15 23:27:25Z],
        epoch: 16,
        session: 5
      },
      %Event{
        start_time: ~U[2022-04-16 01:00:00Z],
        end_time: ~U[2022-04-16 01:27:25Z],
        epoch: 16,
        session: 6
      },
      %Event{
        start_time: ~U[2022-04-16 03:00:00Z],
        end_time: ~U[2022-04-16 03:27:25Z],
        epoch: 16,
        session: 7
      },
      %Event{
        start_time: ~U[2022-04-16 05:00:00Z],
        end_time: ~U[2022-04-16 05:27:25Z],
        epoch: 16,
        session: 8
      },
      %Event{
        start_time: ~U[2022-04-16 07:00:00Z],
        end_time: ~U[2022-04-16 07:27:25Z],
        epoch: 16,
        session: 9
      },
      %Event{
        start_time: ~U[2022-04-16 09:00:00Z],
        end_time: ~U[2022-04-16 09:27:25Z],
        epoch: 16,
        session: 10
      },
      %Event{
        start_time: ~U[2022-04-16 11:00:00Z],
        end_time: ~U[2022-04-16 11:27:25Z],
        epoch: 16,
        session: 11
      },
      %Event{
        start_time: ~U[2022-04-16 13:00:00Z],
        end_time: ~U[2022-04-16 13:27:25Z],
        epoch: 16,
        session: 12
      }
    ]
  end
end
