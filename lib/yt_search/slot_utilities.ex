defmodule YtSearch.SlotUtilities do
  import Ecto.Query
  require Logger
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
            # TODO let the module say if it wants v2 behavior or not
            # this function should be agnostic on the module. no if slot
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
        limit: 30

    Repo.all(query)
    |> then(fn
      [] ->
        raise "we should have already generated an entity id here"

      rows ->
        # the problem statement here is that a request may attempt to use
        # the slot id another request already deleted. this code path only
        # happens in periods of high slot contention (AKA peak time for YTS).

        # when the "best-case" id generation fails (random id), we fall to here
        # which *has* to find an id out. the old solution used the following algorithm:
        #  1. select 1 from the top-N oldest slots
        #  2. delete it, then use its slot id

        # this causes a race condition where one request may use the slot that's
        # already deleted by another request. the probability is 1/N, and we
        # attempted to raise N (from 1 to 30 to 50), to various degrees of success

        # to decrease the probability further while keeping the "worst-case" performance
        # within limits, the algorithm is as follows:
        #  1. select top-N oldest slots
        #  2. delete all of them
        #  3. choose random id from there

        # over time, the id contention window for requests will be lower, because:
        #  1. deleting top-N frees those ids, so they can be used again on the "best-case" id generator
        #  2. if it's under contention, it's highly unlikely two requests will get the
        #     same set of top-N-oldest slots (one of them will have deleted all of them),
        #     so a third request that is operating under contention will have a different
        #     view of top-N-oldest
        chosen_entity =
          rows
          |> Enum.map(fn entity ->
            try do
              Repo.delete(entity)
            rescue
              Ecto.StaleEntryError ->
                Logger.error("got StaleEntryError while deleting #{inspect(entity)}, ignoring!")
            end

            entity
          end)
          |> Enum.random()

        {:ok, chosen_entity.id}
    end)
  end

  defp use_last_slot_assumes_v1(module) do
    query =
      from s in module,
        select: s,
        order_by: [
          asc: fragment("unixepoch(?)", s.inserted_at)
        ],
        limit: 30

    Repo.all(query)
    |> then(fn
      [] ->
        raise "we should have already generated an entity id here"

      rows ->
        chosen_entity =
          rows
          |> Enum.map(fn entity ->
            try do
              Repo.delete(entity)
            rescue
              Ecto.StaleEntryError ->
                Logger.error("got StaleEntryError while deleting #{inspect(entity)}, ignoring!")
            end

            entity
          end)
          |> Enum.random()

        {:ok, chosen_entity.id}
    end)
  end
end
