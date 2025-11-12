defmodule YtSearch.PubSub do
  @moduledoc """
  A high-performance, ETS-backed pub/sub system.

  Subscribers are automatically cleaned up when their process dies.
  Publishing is fast as it reads directly from ETS without going through GenServer.

  ## Examples

      # Subscribe to a topic (subscribes the calling process)
      YtSearch.PubSub.subscribe(:video_updates)

      # Publish to all subscribers
      YtSearch.PubSub.publish(:video_updates, %{video_id: "abc123", action: :updated})

      # Subscribers receive messages as:
      # {:pubsub, topic, message}
  """

  use GenServer
  require Logger

  @table :simple_pubsub_table

  ## Client API

  @doc """
  Starts the PubSub GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes the calling process to a topic.
  The process will receive messages as `{:pubsub, topic, message}`.
  """
  @spec subscribe(atom()) :: :ok
  def subscribe(topic) when is_atom(topic) do
    GenServer.call(__MODULE__, {:subscribe, topic, self()})
  end

  @doc """
  Publishes a message to all subscribers of a topic.
  This is a fast operation that reads directly from ETS.
  """
  @spec publish(atom(), any()) :: :ok
  def publish(topic, message) when is_atom(topic) do
    # Fast ETS lookup - no GenServer call needed
    @table
    |> :ets.lookup(topic)
    |> Enum.each(fn {_topic, pid, _ref} ->
      send(pid, {:pubsub, topic, message})
    end)

    :ok
  end

  @doc """
  Unsubscribes the calling process from a topic.
  """
  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(topic) when is_atom(topic) do
    GenServer.call(__MODULE__, {:unsubscribe, topic, self()})
  end

  @doc """
  Returns the count of subscribers for a topic.
  """
  @spec subscriber_count(atom()) :: non_neg_integer()
  def subscriber_count(topic) when is_atom(topic) do
    @table
    |> :ets.lookup(topic)
    |> length()
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create public ETS table for fast reads
    # Using :bag allows multiple entries per topic
    table = :ets.new(@table, [:bag, :named_table, :public, read_concurrency: true])

    {:ok, %{table: table, monitors: %{}}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    # Monitor the subscriber process
    ref = Process.monitor(pid)

    # Store in ETS: {topic, pid, monitor_ref}
    :ets.insert(state.table, {topic, pid, ref})

    # Track monitor refs to clean up on process death
    monitors = Map.update(state.monitors, ref, [{topic, pid}], fn entries ->
      [{topic, pid} | entries]
    end)

    {:reply, :ok, %{state | monitors: monitors}}
  end

  @impl true
  def handle_call({:unsubscribe, topic, pid}, _from, state) do
    # Find and remove entries for this topic/pid combination
    entries = :ets.match_object(state.table, {topic, pid, :_})

    Enum.each(entries, fn {_topic, _pid, ref} = entry ->
      :ets.delete_object(state.table, entry)
      Process.demonitor(ref, [:flush])
    end)

    # Clean up monitor tracking
    refs = Enum.map(entries, fn {_topic, _pid, ref} -> ref end)
    monitors = Enum.reduce(refs, state.monitors, fn ref, acc -> Map.delete(acc, ref) end)

    {:reply, :ok, %{state | monitors: monitors}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Clean up all entries for this monitor ref
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      entries ->
        Enum.each(entries, fn {topic, pid} ->
          :ets.match_delete(state.table, {topic, pid, ref})
        end)

        monitors = Map.delete(state.monitors, ref)
        {:noreply, %{state | monitors: monitors}}
    end
  end
end
