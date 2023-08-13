defmodule YtSearch.TTL do
  def expired?(%YtSearch.Slot{} = slot) do
    module = YtSearch.Slot
    now = DateTime.utc_now()
    inserted_at = slot.inserted_at |> DateTime.from_naive!("Etc/UTC")
    lifetime = DateTime.diff(now, inserted_at, :second)

    entity_ttl =
      case slot.video_duration do
        nil -> module.default_ttl()
        value -> max(module.min_ttl(), min((4 * value) |> trunc, module.max_ttl()))
      end

    lifetime > entity_ttl
  end

  def expired?(entity, entity_ttl) do
    now = DateTime.utc_now()
    inserted_at = entity.inserted_at |> DateTime.from_naive!("Etc/UTC")
    lifetime = DateTime.diff(now, inserted_at, :second)
    lifetime > entity_ttl
  end

  def maybe?(entity, YtSearch.Slot) do
    cond do
      entity == nil -> nil
      expired?(entity) -> nil
      true -> entity
    end
  end

  def maybe?(entity, entity_module) do
    cond do
      entity == nil -> nil
      expired?(entity, entity_module.ttl()) -> nil
      true -> entity
    end
  end
end
