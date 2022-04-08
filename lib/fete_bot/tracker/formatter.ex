defmodule FeteBot.Tracker.Formatter do
  alias FeteBot.{TimeUtils, WindowMap}

  @alarm_clock "\u{23F0}"

  def generate_schedule(events, now) do
    tagged_events =
      events
      |> Enum.map(&tag_event_time(&1, now))
      |> revise_event_tags()

    [
      header(tagged_events),
      tagged_events |> Enum.map(&event_line_item/1) |> Enum.join("\n"),
      footer()
    ]
    |> Enum.join("\n\n")
  end

  defp header(tagged_events) do
    first = tagged_events |> Enum.at(0)
    last = tagged_events |> Enum.at(-1)

    [
      "Welcome to FFXIV's Fêtes!  Teleport to the Firmament to join in.",
      header_start_text(first, last)
    ]
    |> Enum.join("\n")
  end

  defp header_start_text({:next, first}, _) do
    "The next series of fêtes will begin at #{long_time(first.start_time)}."
  end

  defp header_start_text({:ongoing, first}, _) do
    "The current series of fêtes just began #{relative(first.start_time)}!"
  end

  defp header_start_text({:previous, _}, {_, last}) do
    "The current series of fêtes began recently, and will end #{relative(last.end_time)}."
  end

  defp header_start_text(_, {:future, last}) do
    "A series of fêtes is currently underway, and will end #{relative(last.end_time)}."
  end

  defp header_start_text(_, {tag, last}) when tag in [:next, :ongoing] do
    "The current series of fêtes is almost over, and will end #{relative(last.end_time)}."
  end

  defp header_start_text(_, {:past, _}) do
    raise ArgumentError, "Invalid schedule, all events are in the past"
  end

  defp footer do
    "React with #{@alarm_clock} if you want this bot to send you personal reminders."
  end

  defp tag_event_time(event, now) do
    cond do
      event.end_time |> TimeUtils.is_before_or_at?(now) -> {:past, event}
      event.start_time |> TimeUtils.is_before_or_at?(now) -> {:ongoing, event}
      true -> {:future, event}
    end
  end

  defp revise_event_tags(events) do
    events
    |> WindowMap.prepare()
    |> Enum.map(fn
      {nil, {:future, event}, _} -> {:next, event}
      {_, {:past, event}, {:future, _}} -> {:previous, event}
      {{:past, _}, {:future, event}, _} -> {:next, event}
      {_, as_tagged, _} -> as_tagged
    end)
  end

  defp event_line_item({tag, event}) do
    text =
      case tag do
        :past -> "~~ended at #{timestamp(event.end_time)}~~"
        :previous -> "~~ended #{relative(event.end_time)}~~"
        :ongoing -> "**right now!** (ends #{relative(event.end_time)})"
        :next -> "starts at #{timestamp(event.start_time)} (#{relative(event.start_time)})"
        :future -> "starts at #{timestamp(event.start_time)}"
      end

    session = "##{event.session}" |> String.pad_leading(3)
    "`#{session}:` #{text}"
  end

  defp timestamp(datetime, format \\ "t") do
    "<t:#{DateTime.to_unix(datetime)}:#{format}>"
  end

  defp relative(datetime), do: timestamp(datetime, "R")
  defp long_time(datetime), do: timestamp(datetime, "F")
end
