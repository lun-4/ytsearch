defmodule YtSearch.SlotUtilities do
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.TTL

  def find_available_slot_id(module, url_slots, ttl, max_retries) do
    find_available_slot_id(module, url_slots, ttl, max_retries, 0)
  end

  defmodule RerollCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_slot_reroll_count,
        help: "Total times we rerolled an ID for a given slot",
        labels: [:type]
      )
    end

    def inc(type) do
      Counter.inc(
        name: :yts_slot_reroll_count,
        labels: [to_string(type)]
      )
    end
  end

  @spec find_available_slot_id(atom(), Integer.t(), Integer.t(), Integer.t()) ::
          {:ok, Integer.t()} | {:error, :no_available_id}
  def find_available_slot_id(module, url_slots, ttl, max_retries, current_retry) do
    # generate id, check if 

    random_id = :rand.uniform(url_slots)
    query = from s in module, where: s.id == ^random_id, select: s

    case Repo.one(query) do
      nil ->
        {:ok, random_id}

      slot ->
        # already existing from id, check if it needs to be
        # refreshed
        if TTL.expired?(slot, ttl) do
          Repo.delete!(slot)
          {:ok, random_id}
        else
          Counter.inc(module)

          if current_retry > max_retries do
            {:error, :no_available_id}
          else
            find_available_slot_id(module, url_slots, max_retries, current_retry + 1)
          end
        end
    end
  end
end
