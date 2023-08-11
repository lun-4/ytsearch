defmodule YtSearch.SlotUtilities do
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.TTL

  def find_available_slot_id(module) do
    find_available_slot_id(module, 1)
  end

  @spec find_available_slot_id(atom()) ::
          {:ok, Integer.t()} | {:error, :no_available_id}
  def find_available_slot_id(module, current_retry) do
    # generate id, check if 

    random_id = :rand.uniform(module.urls())
    query = from s in module, where: s.id == ^random_id, select: s

    case Repo.one(query) do
      nil ->
        {:ok, random_id}

      slot ->
        # already existing from id, check if it needs to be
        # refreshed
        is_expired =
          case slot do
            %YtSearch.Slot{} ->
              TTL.expired?(slot)

            _ ->
              TTL.expired?(slot, module.ttl())
          end

        if is_expired do
          Repo.delete!(slot)
          {:ok, random_id}
        else
          if current_retry > module.max_id_retries() do
            case module do
              YtSearch.Slot ->
                use_last_slot_assumes_v2(module)

              _ ->
                use_last_slot_assumes_v1(module)
            end
          else
            find_available_slot_id(module, current_retry + 1)
          end
        end
    end
  end

  defp use_last_slot_assumes_v2(module) do
    # this is the worst case scenario where we are out of ideas on what to do.
    # get the oldest slot id, delete it, and use it.

    query =
      from s in module,
        select: s,
        order_by: [
          asc: s.inserted_at_v2
        ],
        limit: 1

    case Repo.one(query) do
      nil ->
        raise "we should have already generated an entity id here"

      entity ->
        Repo.delete(entity)
        {:ok, entity.id}
    end
  end

  defp use_last_slot_assumes_v1(module) do
    query =
      from s in module,
        select: s,
        order_by: [
          asc: fragment("unixepoch(?)", s.inserted_at)
        ],
        limit: 1

    case Repo.one(query) do
      nil ->
        raise "we should have already generated an entity id here"

      entity ->
        Repo.delete(entity)
        {:ok, entity.id}
    end
  end
end
