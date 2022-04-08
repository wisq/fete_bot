defmodule FeteBot.TimeUtils do
  @doc """
  Does dt1 come before dt2?
  """
  def is_before?(dt1, dt2) do
    Timex.compare(dt1, dt2) == -1
  end

  @doc """
  Does dt1 come before dt2, or are they the same time?

  Equivalent to `!is_after?(dt1, dt2)`
  """
  def is_before_or_at?(dt1, dt2) do
    Timex.compare(dt1, dt2) in [-1, 0]
  end

  @doc """
  Does dt1 come after dt2?
  """
  def is_after?(dt1, dt2) do
    Timex.compare(dt1, dt2) == 1
  end

  @doc """
  Does dt1 come after dt2, or are they the same time?

  Equivalent to `!is_before?(dt1, dt2)`
  """
  def is_after_or_at?(dt1, dt2) do
    Timex.compare(dt1, dt2) in [0, 1]
  end
end
