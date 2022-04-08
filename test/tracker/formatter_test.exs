defmodule FeteBot.Tracker.FormatterTest do
  use FeteBot.TestCase, async: true

  alias FeteBot.Tracker.Formatter

  @events [
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-09 23:00:00Z],
      end_time: ~U[2022-04-09 23:27:25Z],
      epoch: 14,
      session: 1
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 01:00:00Z],
      end_time: ~U[2022-04-10 01:27:25Z],
      epoch: 14,
      session: 2
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 03:00:00Z],
      end_time: ~U[2022-04-10 03:27:25Z],
      epoch: 14,
      session: 3
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 05:00:00Z],
      end_time: ~U[2022-04-10 05:27:25Z],
      epoch: 14,
      session: 4
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 07:00:00Z],
      end_time: ~U[2022-04-10 07:27:25Z],
      epoch: 14,
      session: 5
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 09:00:00Z],
      end_time: ~U[2022-04-10 09:27:25Z],
      epoch: 14,
      session: 6
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 11:00:00Z],
      end_time: ~U[2022-04-10 11:27:25Z],
      epoch: 14,
      session: 7
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 13:00:00Z],
      end_time: ~U[2022-04-10 13:27:25Z],
      epoch: 14,
      session: 8
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 15:00:00Z],
      end_time: ~U[2022-04-10 15:27:25Z],
      epoch: 14,
      session: 9
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 17:00:00Z],
      end_time: ~U[2022-04-10 17:27:25Z],
      epoch: 14,
      session: 10
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 19:00:00Z],
      end_time: ~U[2022-04-10 19:27:25Z],
      epoch: 14,
      session: 11
    },
    %FeteBot.Fetes.Event{
      start_time: ~U[2022-04-10 21:00:00Z],
      end_time: ~U[2022-04-10 21:27:25Z],
      epoch: 14,
      session: 12
    }
  ]

  describe "generate_schedule/2 before first event" do
    test "produces a list of timestamped fetes" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-09 22:59:59Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert lines = body |> String.split("\n")

      lines
      |> Enum.each(fn line ->
        assert %{"n" => n, "t" => t} =
                 Regex.named_captures(~r{^` ?#(?<n>\d+):` starts at <t:(?<t>\d+):t>}, line)

        assert n = String.to_integer(n)
        assert n in 1..12
        assert event = @events |> Enum.at(n - 1)

        assert t = String.to_integer(t) |> DateTime.from_unix!()
        assert t == event.start_time
      end)
    end

    test "puts a relative timestamp on (just) the first event" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-09 22:59:59.999999Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert [line1 | rest] = body |> String.split("\n")

      assert line1 == "` #1:` starts at <t:1649545200:t> (<t:1649545200:R>)"
      rest |> Enum.each(fn line -> assert line =~ ~r{^` ?#\d+:` starts at <t:\d+:t>$} end)
    end

    test "refers to 'the next series of fetes' in the header" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-09 22:59:59.999999Z])
      assert [header, _body, _footer] = text |> String.split("\n\n")
      assert header =~ ~r{The next series of fêtes will begin}
    end

    test "mentions the alarm clock reaction in the footer" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-09 22:59:59.999999Z])
      assert [_header, _body, footer] = text |> String.split("\n\n")
      assert footer |> String.contains?("React with \u{23F0} if")
    end
  end

  describe "generate_schedule/2 during first event" do
    test "has the first event ongoing with an end time" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-09 23:00:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert [line1 | rest] = body |> String.split("\n")

      assert line1 == "` #1:` **right now!** (ends <t:1649546845:R>)"
      rest |> Enum.each(fn line -> assert line =~ ~r{^` ?#\d+:` starts at <t:\d+:t>$} end)
    end

    test "talks about the current series just starting in the header" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-09 23:00:00Z])
      assert [header, _body, _footer] = text |> String.split("\n\n")
      assert header =~ ~r{The current series of fêtes just began}
    end
  end

  describe "generate_schedule/2 after first event" do
    test "crosses out the first event and has relative times for the first two events" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 00:00:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert [line1, line2 | rest] = body |> String.split("\n")

      assert line1 == "` #1:` ~~ended <t:1649546845:R>~~"
      assert line2 == "` #2:` starts at <t:1649552400:t> (<t:1649552400:R>)"
      rest |> Enum.each(fn line -> assert line =~ ~r{^` ?#\d+:` starts at <t:\d+:t>$} end)
    end

    test "talks about the current series starting recently in the header" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 00:00:00Z])
      assert [header, _body, _footer] = text |> String.split("\n\n")
      assert header =~ ~r{The current series of fêtes began recently}
    end
  end

  describe "generate_schedule/2 after sixth event" do
    test "crosses out the first five events" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 10:00:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert lines = body |> String.split("\n", parts: 6) |> Enum.take(5)
      lines |> Enum.each(fn line -> assert line =~ ~r{^` ?#\d+:` ~~ended at <t:\d+:t>~~$} end)
    end

    test "puts relative timestamps on events 6 and 7" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 10:00:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert [line6, line7] = body |> String.split("\n") |> Enum.slice(5..6)

      assert line6 == "` #6:` ~~ended <t:1649582845:R>~~"
      assert line7 == "` #7:` starts at <t:1649588400:t> (<t:1649588400:R>)"
    end

    test "talks about the current series being underway" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 10:00:00Z])
      assert [header, _body, _footer] = text |> String.split("\n\n")
      assert header =~ ~r{A series of fêtes is currently underway}
    end
  end

  describe "generate_schedule/2 after 11th event" do
    test "crosses out the first 10 events" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 20:00:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert lines = body |> String.split("\n") |> Enum.take(10)
      lines |> Enum.each(fn line -> assert line =~ ~r{^` ?#\d+:` ~~ended at <t:\d+:t>~~$} end)
    end

    test "puts relative timestamps on events 11 and 12" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 20:00:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert [line6, line7] = body |> String.split("\n") |> Enum.slice(10..11)

      assert line6 == "`#11:` ~~ended <t:1649618845:R>~~"
      assert line7 == "`#12:` starts at <t:1649624400:t> (<t:1649624400:R>)"
    end

    test "talks about the current series being almost over" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 20:00:00Z])
      assert [header, _body, _footer] = text |> String.split("\n\n")
      assert header =~ ~r{The current series of fêtes is almost over}
    end
  end

  describe "generate_schedule/2 during final event" do
    test "crosses out the first 11 events" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 21:15:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert lines = body |> String.split("\n") |> Enum.take(11)
      lines |> Enum.each(fn line -> assert line =~ ~r{^` ?#\d+:` ~~ended at <t:\d+:t>~~$} end)
    end

    test "has the final event ongoing with an end time" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 21:15:00Z])
      assert [_header, body, _footer] = text |> String.split("\n\n")
      assert line12 = body |> String.split("\n") |> List.last()

      assert line12 == "`#12:` **right now!** (ends <t:1649626045:R>)"
    end

    test "talks about the current series being almost over" do
      assert text = Formatter.generate_schedule(@events, ~U[2022-04-10 21:15:00Z])
      assert [header, _body, _footer] = text |> String.split("\n\n")
      assert header =~ ~r{The current series of fêtes is almost over}
    end
  end

  test "generate_schedule/2 after final event throws an error" do
    err =
      assert_raise(ArgumentError, fn ->
        Formatter.generate_schedule(@events, ~U[2022-04-10 21:27:25Z])
      end)

    assert err.message =~ "all events are in the past"
  end
end
