defmodule FetesTest do
  use ExUnit.Case
  alias FeteBot.Fetes
  alias FeteBot.Fetes.Event

  @hour 3600
  @day 24 * @hour
  @week 7 * @day

  test "generates a calendar around now" do
    assert events = Fetes.calendar()

    # Get event times:
    %Event{start_time: first_dt} = events |> List.first()
    %Event{start_time: last_dt} = events |> List.last()
    first = first_dt |> DateTime.to_unix()
    last = last_dt |> DateTime.to_unix()

    # First and last events are 22 hours apart
    assert last - first == @hour * 22

    # First and last events are within one week of now
    assert now = DateTime.utc_now() |> DateTime.to_unix()
    assert_in_delta first, now, @week
    assert_in_delta last, now, @week
  end

  test "generates calendar around specific time" do
    assert events = Fetes.calendar(~U[2022-04-10 20:00:00Z])

    assert %Event{
             start_time: ~U[2022-04-09 23:00:00Z],
             end_time: ~U[2022-04-09 23:27:25Z],
             epoch: 14,
             session: 1
           } = events |> List.first()

    assert %Event{
             start_time: ~U[2022-04-10 05:00:00Z],
             end_time: ~U[2022-04-10 05:27:25Z],
             epoch: 14,
             session: 4
           } = events |> Enum.at(3)

    assert %Event{
             start_time: ~U[2022-04-10 21:00:00Z],
             end_time: ~U[2022-04-10 21:27:25Z],
             epoch: 14,
             session: 12
           } = events |> List.last()
  end

  test "sessions are separated by two hours" do
    assert events = Fetes.calendar(~U[2022-05-01 00:00:00Z])

    assert %Event{start_time: start1} = events |> Enum.at(7)
    assert %Event{start_time: start2} = events |> Enum.at(8)

    assert DateTime.to_unix(start2) - DateTime.to_unix(start1) == @hour * 2
  end

  test "epochs are separated by 68 hours" do
    now = DateTime.utc_now()
    assert events1 = Fetes.calendar(now)
    assert %Event{start_time: start1, epoch: epoch1} = events1 |> List.first()

    then = now |> DateTime.add(68 * @hour)
    assert events2 = Fetes.calendar(then)
    assert %Event{start_time: start2, epoch: epoch2} = events2 |> List.first()

    assert epoch2 == epoch1 + 1
    assert DateTime.to_unix(start2) - DateTime.to_unix(start1) == @hour * 68
  end
end
