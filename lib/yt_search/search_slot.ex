defmodule YtSearch.SearchSlot do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.SearchSlotRepo
  alias YtSearch.Slot
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot
  alias YtSearch.SlotUtilities
  import Ecto.Changeset
  require Logger

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  schema "search_slots_v3" do
    field(:slots_json, :string, default: "")
    field(:query, :string, default: "")
    timestamps(autogenerate: {SlotUtilities, :generate_unix_timestamp, []})
    field(:expires_at, :naive_datetime)
    field(:used_at, :naive_datetime)
    field(:keepalive, :boolean)
    field(:nextpage_data, :string)
    field(:type, Ecto.Enum, values: [:fetched, :unfetched])
    field(:nextpage_slot_id, :integer)
  end

  def slot_spec() do
    %{
      max_ids: 10_000,
      ttl: 20 * 60
    }
  end

  @spec fetch(Integer.t()) :: SearchSlot.t() | nil
  def fetch(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s

    SearchSlotRepo.replica(slot_id).one(query)
    |> SlotUtilities.strict_ttl()
  end

  defp internal_id_for(%ChannelSlot{youtube_id: channel_id}) do
    "ytchannel://#{channel_id}"
  end

  defp internal_id_for(%PlaylistSlot{youtube_id: playlist_id}) do
    "ytplaylist://#{playlist_id}"
  end

  defp internal_id_for(%__MODULE__{id: id}) do
    "ytsearchslot://#{id}"
  end

  defp internal_id_for(text) when is_bitstring(text) do
    "ytsearch://#{text}"
  end

  def fetch_by_query(query) do
    internal_id = query |> internal_id_for
    query = from s in __MODULE__, where: s.query == ^internal_id, select: s

    SearchSlotRepo.replica(internal_id).one(query)
    |> SlotUtilities.strict_ttl()
  end

  def get_slots(search_slot) do
    search_slot.slots_json
    |> Jason.decode!()
  end

  def fetched_slots_from_search(search_slot) do
    search_slot
    |> get_slots
    |> Enum.map(fn %{"type" => slot_type, "youtube_id" => youtube_id} = maybe_slot ->
      # assumes all slot types are "strict ttl" as in,
      # fetches won't give nil values if the respective slots
      # are going to be obliterated any time now
      case slot_type do
        t when t in ["video", "short", "livestream"] ->
          Slot.fetch_by_youtube_id(youtube_id)

        "playlist" ->
          PlaylistSlot.fetch_by_youtube_id(youtube_id)

        "channel" ->
          ChannelSlot.fetch_by_youtube_id(youtube_id)

        nil ->
          Logger.warning("invalid type from #{inspect(maybe_slot)}")
          nil

        _ ->
          raise "invalid type for search slot entry: #{inspect(slot_type)}"
      end
    end)
  end

  def changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [
      :id,
      :query,
      :slots_json,
      :expires_at,
      :used_at,
      :keepalive,
      :nextpage_data,
      :type
    ])
    |> validate_required([:expires_at, :used_at, :type])
    |> validate_not_nil([:query, :slots_json])
  end

  defp validate_not_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if get_field(changeset, field) == nil do
        add_error(changeset, field, "is fckin nil")
      else
        changeset
      end
    end)
  end

  def from_playlist(playlist, search_query, opts \\ []) do
    nextpage = opts |> Keyword.get(:nextpage?, false)

    if nextpage do
      nextpage_slot = from_nextpage(search_query, playlist.nextpage)

      {playlist.results
       |> Jason.encode!()
       |> from_slots_json(
         search_query |> internal_id_for,
         opts |> Keyword.put(:nextpage_slot, nextpage_slot)
       ), nextpage_slot}
    else
      playlist
      |> Jason.encode!()
      |> from_slots_json(search_query |> internal_id_for, opts)
    end
  end

  def from_unfetched_slot(playlist, unfetched_slot, search_query) do
    nextpage_slot = from_nextpage(search_query, playlist.nextpage)

    slot =
      playlist.results
      |> Jason.encode!()
      |> from_slots_json(unfetched_slot.query, nextpage_slot: nextpage_slot)

    {slot, nextpage_slot}
  end

  @spec from_slots_json(String.t(), String.t(), Keyword.t()) :: SearchSlot.t()
  defp from_slots_json(slots_json, search_query, opts) do
    keepalive = Keyword.get(opts, :keepalive, false)

    nextpage_slot_id =
      case Keyword.get(opts, :nextpage_slot, nil) do
        nil -> nil
        v -> v.id
      end

    SearchSlotRepo.transaction(fn ->
      query = from s in __MODULE__, where: s.query == ^search_query, select: s
      search_slot = SearchSlotRepo.replica(search_query).one(query)

      if search_slot == nil do
        {:ok, new_id} = SlotUtilities.generate_id_v3(__MODULE__)

        params =
          %{
            id: new_id,
            query: search_query,
            slots_json: slots_json,
            keepalive: keepalive,
            type: :fetched,
            nextpage_slot_id: nextpage_slot_id
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_used()

        %__MODULE__{}
        |> changeset(params)
        |> SearchSlotRepo.insert!(
          on_conflict: [
            set: [
              query: params.query,
              slots_json: params.slots_json,
              expires_at: params.expires_at,
              used_at: params.used_at,
              keepalive: params.keepalive,
              nextpage_slot_id: params.nextpage_slot_id,
              type: :fetched
            ]
          ]
        )
      else
        search_slot
        |> changeset(
          %{
            slots_json: slots_json,
            keepalive: keepalive,
            nextpage_slot_id: nextpage_slot_id,
            type: :fetched
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_opts(opts)
          |> SlotUtilities.put_used()
        )
        |> SearchSlotRepo.update!()
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
  end

  def unpack_nextpage(slot),
    do:
      slot.nextpage_data
      |> Jason.decode!()
      |> then(fn
        %{"v" => 1, "q" => q, "n" => n} -> {q, n}
      end)

  defp from_nextpage(_, nil), do: nil

  defp from_nextpage(query, nextpage_queryparam) do
    nextpage_packed =
      %{
        v: 1,
        q:
          case query do
            v when is_bitstring(v) -> v
            %{youtube_id: ytid} -> ytid
          end,
        n: nextpage_queryparam
      }
      |> Jason.encode!()

    SearchSlotRepo.transaction(fn ->
      query =
        from s in __MODULE__,
          where: not is_nil(s.nextpage_data) and s.nextpage_data == ^nextpage_packed,
          select: s

      search_slot = SearchSlotRepo.replica(nextpage_packed).one(query)

      if search_slot == nil do
        {:ok, new_id} = SlotUtilities.generate_id_v3(__MODULE__)

        params =
          %{
            id: new_id,
            slots_json: "",
            query: internal_id_for(%__MODULE__{id: new_id}),
            nextpage_data: nextpage_packed,
            type: :unfetched,
            keepalive: false
          }
          # TODO (DO NOT MERGE) set expiration based on the parent
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_used()

        %__MODULE__{}
        |> changeset(params)
        |> SearchSlotRepo.insert!(
          on_conflict: [
            set: [
              query: params.query,
              slots_json: params.slots_json,
              nextpage_data: params.nextpage_data,
              type: params.type,
              expires_at: params.expires_at,
              used_at: params.used_at,
              keepalive: false
            ]
          ]
        )
      else
        search_slot
        |> changeset(
          %{
            query: internal_id_for(%__MODULE__{id: search_slot.id}),
            slots_json: "",
            nextpage_data: nextpage_packed,
            type: :unfetched,
            keepalive: false
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_used()
        )
        |> SearchSlotRepo.update!()
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
  end

  def urls, do: 0
end
