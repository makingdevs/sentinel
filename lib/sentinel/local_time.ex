defmodule Sentinel.LocalTime do
  @moduledoc "Application calendar and display in Mexico City standard time (UTC−06:00)."

  @utc_offset_seconds -6 * 60 * 60

  def today, do: DateTime.utc_now() |> date()

  def date(datetime), do: datetime |> local_naive() |> NaiveDateTime.to_date()

  def midnight_utc(date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.add(-@utc_offset_seconds)
  end

  def format(datetime, pattern \\ "%Y-%m-%d %H:%M:%S"),
    do: datetime |> local_naive() |> Calendar.strftime(pattern)

  def relative(datetime, now) do
    seconds = max(0, DateTime.diff(now, datetime))
    days = Date.diff(date(now), date(datetime))

    cond do
      seconds < 60 -> "hace un momento"
      seconds < 3600 -> "hace #{div(seconds, 60)} min"
      days == 1 -> "ayer"
      days > 1 -> "hace #{days} días"
      true -> "hace #{div(seconds, 3600)} h"
    end
  end

  def duration(from, until) do
    seconds = DateTime.diff(until, from)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    remainder = rem(seconds, 60)

    cond do
      hours > 0 -> "#{hours} h #{minutes} min"
      minutes > 0 -> "#{minutes} min #{remainder} s"
      true -> "#{remainder} s"
    end
  end

  defp local_naive(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
    |> NaiveDateTime.add(@utc_offset_seconds)
  end
end
