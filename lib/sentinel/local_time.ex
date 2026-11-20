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

  defp local_naive(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
    |> NaiveDateTime.add(@utc_offset_seconds)
  end
end
