defmodule Sentinel.Monitoring.CameraSource do
  @moduledoc "Server-only RTSP connection for one camera and quality."
  use Ecto.Schema
  import Ecto.Changeset

  schema "camera_sources" do
    belongs_to :camera, Sentinel.Monitoring.Camera, type: :string
    field :quality, :string
    field :url, :string, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:quality, :url])
    |> validate_required([:camera_id, :quality, :url])
    |> validate_inclusion(:quality, ~w(principal secundaria))
    |> validate_change(:url, fn :url, url ->
      if valid_url?(url), do: [], else: [url: "must be an RTSP URL with a host"]
    end)
    |> foreign_key_constraint(:camera_id)
    |> unique_constraint([:camera_id, :quality])
    |> check_constraint(:quality, name: :camera_sources_quality_check)
    |> check_constraint(:url, name: :camera_sources_url_check)
  end

  def valid_url?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "rtsp", host: host}} when is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  def valid_url?(_url), do: false
end
