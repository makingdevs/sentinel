defmodule Sentinel.TestMediaProcess do
  use GenServer, restart: :temporary

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def init(options) do
    send(Application.fetch_env!(:sentinel, :media_test_owner), {:media_started, self(), options})
    {:ok, options}
  end
end
