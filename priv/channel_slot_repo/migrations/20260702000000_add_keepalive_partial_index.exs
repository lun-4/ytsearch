defmodule YtSearch.Data.ChannelSlotRepo.Migrations.AddKeepalivePartialIndex do
  use Ecto.Migration

  def change do
    # lets the usage meter count keepalive slots without a full-table scan;
    # keyed on the expiry expression so `keepalive AND unixepoch(expires_at) <= ?`
    # is answered entirely from this (small) partial index
    create index(:channel_slots_v3, ["unixepoch(expires_at)"],
             where: "keepalive",
             name: :channel_slots_v3_keepalive_partial
           )
  end
end
