defmodule YtSearch.TTL do
  def expired?(entity, entity_ttl) do
    now = DateTime.utc_now()
    inserted_at = entity.inserted_at |> DateTime.from_naive!("Etc/UTC")
    lifetime = DateTime.diff(now, inserted_at, :second)
    lifetime > entity_ttl
  end
end