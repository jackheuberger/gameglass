defmodule Gameglass.Ingest.Refresher do
  @moduledoc """
  Supervised runner around `Gameglass.Ingest.refresh/1`. It owns *when* a refresh
  happens while keeping the crawl logic itself scheduler-agnostic.

  v1 is manual-trigger only (`refresh_async/0`), but it is structured so a
  periodic tick can be added later (or the call swapped for a job system) without
  touching the ingestion pipeline. Refreshes never overlap: a request received
  while one is running is ignored.

  Subscribe to `"ingest"` on `Gameglass.PubSub` to receive `{:ingest, status}`
  broadcasts (`:started`, `{:finished, summary}`, `{:failed, reason}`).
  """
  use GenServer

  require Logger

  @topic "ingest"

  # --- client API ------------------------------------------------------------

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Triggers a refresh in the background. Returns `:ok` or `:already_running`."
  def refresh_async, do: GenServer.call(__MODULE__, :refresh)

  @doc "Current status: `:idle` or `:running`."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Last completed run's summary, or `nil`."
  def last_result, do: GenServer.call(__MODULE__, :last_result)

  def topic, do: @topic

  # --- server ----------------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok, %{task: nil, last_result: nil, opts: opts}}
  end

  @impl true
  def handle_call(:refresh, _from, %{task: nil} = state) do
    {:reply, :ok, %{state | task: start_task(state.opts)}}
  end

  def handle_call(:refresh, _from, state), do: {:reply, :already_running, state}

  def handle_call(:status, _from, state) do
    {:reply, if(state.task, do: :running, else: :idle), state}
  end

  def handle_call(:last_result, _from, state), do: {:reply, state.last_result, state}

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, summary} -> broadcast({:finished, summary})
      {:error, reason} -> broadcast({:failed, reason})
    end

    {:noreply, %{state | task: nil, last_result: result}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{task: %Task{}} = state) do
    Logger.error("Gameglass ingest task crashed: #{inspect(reason)}")
    broadcast({:failed, reason})
    {:noreply, %{state | task: nil, last_result: {:error, reason}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp start_task(opts) do
    broadcast(:started)
    Task.async(fn -> Gameglass.Ingest.refresh(opts) end)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Gameglass.PubSub, @topic, {:ingest, message})
  end
end
