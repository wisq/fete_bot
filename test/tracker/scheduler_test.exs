defmodule FeteBot.Tracker.SchedulerTest do
  use FeteBot.TestCase, async: false

  alias Timex.Duration
  alias FeteBot.Tracker.Scheduler
  alias FeteBot.Test.{MockDateTime, MockGenServer, MockDiscord}
  alias FeteBot.Test.DataFactory
  alias FeteBot.Fetes.Event

  defmodule FakeNotifierScheduler do
    use GenServer
    @name FeteBot.Notifier.Scheduler

    def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: @name)
    def init(_), do: {:ok, nil}
    def handle_cast({:next_event, event}, _), do: {:noreply, event}
    def handle_call(:get, _from, event), do: {:reply, event, nil}

    def get, do: GenServer.call(@name, :get)
  end

  defp start_scheduler(start_time) do
    MockDateTime.child_spec(start_time)
    |> start_supervised!()

    MockGenServer.child_spec(Scheduler)
    |> start_supervised!()
    |> MockDateTime.add_server()
  end

  @alarm_clock "\u{23F0}"

  test "tracker scheduler sends schedule to registered channels shortly after startup" do
    channels = [
      DataFactory.insert!(:channel),
      DataFactory.insert!(:channel),
      DataFactory.insert!(:channel)
    ]

    pid = start_scheduler(~U[2022-04-11 00:00:00Z])

    MockDateTime.advance_by(Duration.from_minutes(1))

    # Three messages created, and a reaction put on each:
    assert [
             {:create_message, {channel_id_1, "Welcome" <> _}},
             {:create_reaction, {channel_id_1, message_id_1, @alarm_clock}},
             {:create_message, {channel_id_2, "Welcome" <> _}},
             {:create_reaction, {channel_id_2, message_id_2, @alarm_clock}},
             {:create_message, {channel_id_3, "Welcome" <> _}},
             {:create_reaction, {channel_id_3, message_id_3, @alarm_clock}}
           ] = MockDiscord.messages(pid)

    # The Channel records are updated with the message IDs:
    assert channels
           |> Enum.map(&Repo.reload!/1)
           |> Map.new(&{&1.channel_id, &1.message_id}) == %{
             channel_id_1 => message_id_1,
             channel_id_2 => message_id_2,
             channel_id_3 => message_id_3
           }
  end

  test "tracker scheduler updates schedule at the start and end of each fete" do
    channel = DataFactory.insert!(:channel)
    channel_id = channel.channel_id
    pid = start_scheduler(~U[2022-04-11 00:00:00Z])

    # Initial message:
    MockDateTime.advance_by(Duration.from_minutes(1))

    assert [
             {:create_message, {^channel_id, text}},
             {:create_reaction, {^channel_id, message_id, @alarm_clock}}
           ] = MockDiscord.messages(pid)

    assert text =~ "` #1:` starts "

    assert channel = Repo.reload(channel)
    assert ^message_id = channel.message_id

    # First fete starts:
    MockDateTime.advance_to(~U[2022-04-12 18:59:59Z])
    assert [] = MockDiscord.messages(pid)
    MockDateTime.advance_to(~U[2022-04-12 19:00:01Z])

    assert [
             {:edit_message, {^channel_id, ^message_id, text}},
             {:create_reaction, {^channel_id, ^message_id, @alarm_clock}}
           ] = MockDiscord.messages(pid)

    assert text =~ "` #1:` **right now!**"
    assert text =~ "` #2:` starts "

    # First fete ends:
    MockDateTime.advance_to(~U[2022-04-12 19:25:00Z])
    assert [] = MockDiscord.messages(pid)
    MockDateTime.advance_to(~U[2022-04-12 19:30:00Z])

    assert [
             {:edit_message, {^channel_id, ^message_id, text}},
             {:create_reaction, {^channel_id, ^message_id, @alarm_clock}}
           ] = MockDiscord.messages(pid)

    assert text =~ "` #1:` ~~ended "
    assert text =~ "` #2:` starts "

    # Second fete starts:
    MockDateTime.advance_to(~U[2022-04-12 20:59:59Z])
    assert [] = MockDiscord.messages(pid)
    MockDateTime.advance_to(~U[2022-04-12 21:00:01Z])

    assert [
             {:edit_message, {^channel_id, ^message_id, text}},
             {:create_reaction, {^channel_id, ^message_id, @alarm_clock}}
           ] = MockDiscord.messages(pid)

    assert text =~ "` #1:` ~~ended "
    assert text =~ "` #2:` **right now!** "
  end

  test "tracker scheduler sends the next event to the notifier scheduler" do
    start_supervised!(FakeNotifierScheduler)
    start_scheduler(~U[2022-04-11 00:00:00Z])

    # Initial event:
    MockDateTime.advance_by(Duration.from_minutes(1))
    assert %Event{epoch: 15, session: 1} = FakeNotifierScheduler.get()

    # First fete starts:
    MockDateTime.advance_to(~U[2022-04-12 19:00:01Z])
    assert %Event{epoch: 15, session: 2} = FakeNotifierScheduler.get()

    # Currently we actually send another event once the first fete ends.
    # It's unnecessary, but not particularly harmful, since the notifier can
    # safely handle seeing the same event multiple times.

    # Second fete starts:
    MockDateTime.advance_to(~U[2022-04-12 21:00:01Z])
    assert %Event{epoch: 15, session: 3} = FakeNotifierScheduler.get()

    # Final fete about to start:
    MockDateTime.advance_to(~U[2022-04-13 16:59:59Z])
    assert %Event{epoch: 15, session: 12} = FakeNotifierScheduler.get()

    # Currently we wait until the END of the final fete to send the next epoch:
    MockDateTime.advance_to(~U[2022-04-13 17:30:00Z])
    assert %Event{epoch: 16, session: 1} = FakeNotifierScheduler.get()
  end

  test "tracker scheduler runs through a whole series of fetes" do
    DataFactory.insert!(:channel)
    pid = start_scheduler(~U[2022-04-11 00:00:00Z])

    # Get the initial message out of the way:
    MockDateTime.advance_by(Duration.from_minutes(1))
    assert [{:create_message, _}, {:create_reaction, _}] = MockDiscord.messages(pid)

    # Advance +2 days, through the entire series:
    MockDateTime.advance_to(~U[2022-04-14 00:00:00Z])

    # Twelve fetes, so twenty-four edits (and reactions):
    assert MockDiscord.messages(pid)
           |> Enum.group_by(fn {op, _} -> op end)
           |> Map.new(fn {op, events} -> {op, Enum.count(events)} end) == %{
             edit_message: 24,
             create_reaction: 24
           }
  end

  test "tracker scheduler can handle starting in the middle of a series" do
    start_supervised!(FakeNotifierScheduler)
    DataFactory.insert!(:channel)
    pid = start_scheduler(~U[2022-04-13 06:00:00Z])

    # Initial message, inbetween sessions 6 and 7.
    MockDateTime.advance_by(Duration.from_minutes(1))
    assert %Event{epoch: 15, session: 7} = FakeNotifierScheduler.get()
    assert [{:create_message, {_, text}}, {:create_reaction, _}] = MockDiscord.messages(pid)
    assert text =~ "` #6:` ~~ended "
    assert text =~ "` #7:` starts "

    # Next message at fete 7:
    MockDateTime.advance_to(~U[2022-04-13 06:59:59Z])
    assert nil == FakeNotifierScheduler.get()
    assert [] = MockDiscord.messages(pid)
    MockDateTime.advance_to(~U[2022-04-13 07:00:01Z])
    assert %Event{epoch: 15, session: 8} = FakeNotifierScheduler.get()
    assert [{:edit_message, {_, _, text}}, {:create_reaction, _}] = MockDiscord.messages(pid)
    assert text =~ "` #7:` **right now!** "
  end

  test "tracker scheduler with no channels does nothing" do
    pid = start_scheduler(~U[2022-04-11 00:00:00Z])
    MockDateTime.advance_by(Duration.from_days(2))
    assert [] = MockDiscord.messages(pid)
  end
end
