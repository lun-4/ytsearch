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
    field(:nextpage_data_hash, :string)
    field(:type, Ecto.Enum, values: [:fetched, :unfetched])
    field(:nextpage_slot_id, :integer)
    field(:result_type, Ecto.Enum, values: [:text, :video, :playlist, :channel])
    field(:result_title, :string)
  end

  def slot_spec() do
    %{
      max_ids: 30_000,
      ttl: 20 * 60
    }
  end

  @spec fetch(Integer.t()) :: SearchSlot.t() | nil
  @spec fetch(String.t()) :: SearchSlot.t() | nil
  def fetch(s) when is_bitstring(s), do: fetch(String.to_integer(s))

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
    case search_slot.type do
      nil ->
        search_slot.slots_json
        |> Jason.decode!()

      :fetched ->
        search_slot.slots_json
        |> Jason.decode!()

      :unfetched ->
        []
    end
  end

  def fetched_slots_from_search(search_slot, opts \\ []) do
    follow_inner_channel? = Keyword.get(opts, :follow_inner_channel, false)
    follow_nextpage? = Keyword.get(opts, :follow_nextpage, false)
    is_luna? = Keyword.get(opts, :luna, false)

    Logger.info(
      "LUNA: exec #{search_slot.id} q=#{inspect(search_slot.query)} t=#{inspect(search_slot.type)} nph=#{inspect(search_slot.nextpage_data_hash)}"
    )

    search_slot
    |> get_slots
    |> Enum.map(fn %{"type" => slot_type, "youtube_id" => youtube_id} = maybe_slot ->
      # assumes all slot types are "strict ttl" as in,
      # fetches won't give nil values if the respective slots
      # are going to be obliterated any time now
      case slot_type do
        t when t in ["video", "short", "livestream"] ->
          channel_slot_id = maybe_slot["channel_slot"]

          if follow_inner_channel? do
            if channel_slot_id == nil do
              raise "no channel slot in #{inspect(maybe_slot)}"
            end

            [
              Slot.fetch_by_youtube_id(youtube_id),
              ChannelSlot.fetch(channel_slot_id)
            ]
          else
            [
              Slot.fetch_by_youtube_id(youtube_id)
            ]
          end

        "playlist" ->
          [
            PlaylistSlot.fetch_by_youtube_id(youtube_id)
          ]

        "channel" ->
          [
            ChannelSlot.fetch_by_youtube_id(youtube_id)
          ]

        nil ->
          Logger.warning("invalid type from #{inspect(maybe_slot)}")
          nil

        _ ->
          raise "invalid type for search slot entry: #{inspect(slot_type)}"
      end
    end)
    |> List.flatten()
    |> then(fn slots ->
      if is_luna? do
        Logger.info("LUNA: found #{length(slots)} slots for #{search_slot.id}")
      end

      slots
    end)
    |> then(fn slots ->
      if follow_nextpage? do
        nextpage_slot_id =
          case search_slot.type do
            :fetched -> search_slot.nextpage_slot_id
            :unfetched -> nil
          end

        case nextpage_slot_id do
          nil ->
            slots

          v ->
            maybe_nextpage_slot = fetch(v)

            case maybe_nextpage_slot do
              nil ->
                slots

              nextpage_slot ->
                Logger.info("LUNA: at #{search_slot.id}, going to #{nextpage_slot.id}")

                results =
                  slots ++
                    [nextpage_slot] ++
                    fetched_slots_from_search(nextpage_slot, opts |> Keyword.put(:luna, true))

                Logger.info("LUNA: finished for #{search_slot.id}. results #{length(results)}")
                results
            end
        end
      else
        slots
      end
    end)
  end

  def fetch_all_nextpages(parent_slot), do: fetch_all_nextpages(parent_slot, [])

  def fetch_all_nextpages(parent_slot, current) do
    case parent_slot.nextpage_slot_id do
      nil ->
        current

      v ->
        current ++ [fetch(v)]
    end
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
      :nextpage_data_hash,
      :nextpage_slot_id,
      :result_type,
      :result_title,
      :type
    ])
    |> validate_required([:expires_at, :used_at])
    |> validate_not_nil([:query, :slots_json])
    |> unique_constraint(:query)
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
         opts
         |> Keyword.put(:nextpage_slot, nextpage_slot)
         |> Keyword.put(:result_type, playlist.type)
         |> Keyword.put(:result_title, playlist.title)
       ), nextpage_slot}
    else
      playlist
      |> Jason.encode!()
      |> from_slots_json(search_query |> internal_id_for, opts)
    end
  end

  def from_unfetched_slot(playlist, unfetched_slot) do
    nextpage_slot = from_nextpage(unfetched_slot, playlist.nextpage)

    slot =
      playlist.results
      |> Jason.encode!()
      |> from_slots_json(unfetched_slot |> internal_id_for, nextpage_slot: nextpage_slot)

    {slot, nextpage_slot}
  end

  defp micro_assert!(v), do: micro_assert!(v, "<no msg>")
  defp micro_assert!(true, _), do: nil

  defp micro_assert!(val, msg) do
    raise("tripped assertion! got #{inspect(val)}, should be true! msg=#{msg}")
  end

  def validate_slot_type_fields!(slot) do
    case slot.type do
      :fetched ->
        micro_assert!(
          String.starts_with?(slot.query, "ytsearch://") or
            String.starts_with?(slot.query, "ytchannel://") or
            String.starts_with?(slot.query, "ytplaylist://") or
            slot.query == "ytsearchslot://#{slot.id}",
          "#{slot.type}, #{slot.id}, #{slot.query}"
        )

        micro_assert!(slot.nextpage_data_hash == nil)
        micro_assert!(slot.nextpage_data == nil)
        slot

      :unfetched ->
        micro_assert!(
          slot.query == "ytsearchslot://#{slot.id}",
          "#{slot.type}, #{slot.id}, #{slot.query}"
        )

        micro_assert!(String.length(slot.nextpage_data_hash) > 0)
        micro_assert!(String.length(slot.nextpage_data) > 0)
        micro_assert!(slot.nextpage_slot_id == nil)
        slot
    end
  end

  @spec from_slots_json(String.t(), String.t(), Keyword.t()) :: SearchSlot.t()
  defp from_slots_json(slots_json, search_query, opts) do
    keepalive = Keyword.get(opts, :keepalive, false)

    nextpage_slot_id =
      case Keyword.get(opts, :nextpage_slot, nil) do
        nil -> nil
        v -> v.id
      end

    result_type = Keyword.get(opts, :result_type)
    result_title = Keyword.get(opts, :result_title)

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
            nextpage_slot_id: nextpage_slot_id,
            result_type: result_type,
            result_title: result_title,
            nextpage_data: nil,
            nextpage_data_hash: nil
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
              result_type: params.result_type,
              result_title: params.result_title,
              type: params.type,
              nextpage_data: params.nextpage_data,
              nextpage_data_hash: params.nextpage_data_hash
            ]
          ]
        )
        |> validate_slot_type_fields!
      else
        search_slot
        |> changeset(
          %{
            slots_json: slots_json,
            keepalive: keepalive,
            nextpage_slot_id: nextpage_slot_id,
            result_type: result_type,
            result_title: result_title,
            type: :fetched,
            nextpage_data: nil,
            nextpage_data_hash: nil
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_opts(opts)
          |> SlotUtilities.put_used()
        )
        |> SearchSlotRepo.update!()
        |> validate_slot_type_fields!
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
    |> validate_slot_type_fields!
  end

  def unpack_nextpage(slot),
    do:
      slot.nextpage_data
      |> Jason.decode!()
      |> then(fn
        %{"v" => 1, "t" => t, "q" => q, "n" => n} -> {t, q, n}
      end)

  defp from_nextpage(_, nil), do: nil

  defp from_nextpage(query, nextpage_queryparam) do
    nextpage_packed =
      %{
        v: 1,
        t:
          case query do
            v when is_bitstring(v) ->
              "s"

            %ChannelSlot{} ->
              "c"

            %PlaylistSlot{} ->
              "p"

            %__MODULE__{} = query_slot ->
              query_slot
              |> unpack_nextpage
              |> then(fn {t, _, _} -> t end)
          end,
        q:
          case query do
            v when is_bitstring(v) ->
              v

            %__MODULE__{} = query_slot ->
              query_slot
              |> unpack_nextpage
              |> then(fn {_, q, _} -> q end)

            %{youtube_id: ytid} ->
              ytid
          end,
        n: nextpage_queryparam
      }
      |> Jason.encode!()

    nextpage_packed_hash = :erlang.phash2(nextpage_packed) |> to_string |> :base64.encode()

    SearchSlotRepo.transaction(fn ->
      query =
        from s in __MODULE__,
          where:
            not is_nil(s.nextpage_data_hash) and s.nextpage_data_hash == ^nextpage_packed_hash,
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
            nextpage_data_hash: nextpage_packed_hash,
            nextpage_slot_id: nil,
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
              nextpage_data_hash: params.nextpage_data_hash,
              nextpage_slot_id: params.nextpage_slot_id,
              type: params.type,
              expires_at: params.expires_at,
              used_at: params.used_at,
              keepalive: false
            ]
          ]
        )
        |> validate_slot_type_fields!
      else
        search_slot
        |> changeset(
          %{
            query: internal_id_for(%__MODULE__{id: search_slot.id}),
            slots_json: "",
            nextpage_data: nextpage_packed,
            nextpage_data_hash: nextpage_packed_hash,
            nextpage_slot_id: nil,
            type: :unfetched,
            keepalive: false
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_used()
        )
        |> SearchSlotRepo.update!()
        |> validate_slot_type_fields!
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
    |> validate_slot_type_fields!
  end

  def urls, do: 0
end
