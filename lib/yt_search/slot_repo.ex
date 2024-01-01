defmodule YtSearch.Data do
  defmodule RepoBase do
    defmacro __using__(opts) do
      quote bind_quoted: [opts: opts] do
        use Ecto.Repo,
          otp_app: :yt_search,
          adapter: Ecto.Adapters.SQLite3,

          # sqlite does not do multi-writer. pool_size is effectively one,
          # if it's larger than one, then Database Busy errors haunt you
          # the trick to make concurrency happen is to create "read replicas"
          # that are effectively a pool of readers. this works because we're in WAL mode
          pool_size: 1,
          loggers: [YtSearch.Repo.Instrumenter, Ecto.LogEntry]

        @read_replicas opts[:read_replicas]
        @dedicated_replicas opts[:dedicated_replicas]

        def repo_spec do
          %{read_replicas: @read_replicas, dedicated_replicas: @dedicated_replicas}
        end

        def replica() do
          Enum.random(@read_replicas)
        end

        def replica(identifier)
            when is_number(identifier) or is_bitstring(identifier) or is_atom(identifier) do
          @read_replicas |> Enum.at(rem(identifier |> :erlang.phash2(), length(@read_replicas)))
        end

        for repo <- @read_replicas ++ @dedicated_replicas do
          default_dynamic_repo =
            if Mix.env() == :test do
              opts[:primary]
            else
              repo
            end

          defmodule repo do
            use Ecto.Repo,
              otp_app: :yt_search,
              adapter: Ecto.Adapters.SQLite3,
              pool_size: 1,
              loggers: [YtSearch.Repo.Instrumenter, Ecto.LogEntry],
              read_only: true,
              default_dynamic_repo: default_dynamic_repo
          end
        end
      end
    end
  end

  defmodule SlotRepo do
    use YtSearch.Data.RepoBase,
      primary: YtSearch.Data.SlotRepo,
      read_replicas: [
        YtSearch.Data.SlotRepo.Replica1,
        YtSearch.Data.SlotRepo.Replica2
      ],
      dedicated_replicas: []
  end

  defmodule ChannelSlotRepo do
    use YtSearch.Data.RepoBase,
      primary: YtSearch.Data.ChannelSlotRepo,
      read_replicas: [
        YtSearch.Data.ChannelSlotRepo.Replica1,
        YtSearch.Data.ChannelSlotRepo.Replica2
      ],
      dedicated_replicas: []
  end

  defmodule PlaylistSlotRepo do
    use YtSearch.Data.RepoBase,
      primary: YtSearch.Data.PlaylistSlotRepo,
      read_replicas: [
        YtSearch.Data.PlaylistSlotRepo.Replica1,
        YtSearch.Data.PlaylistSlotRepo.Replica2
      ],
      dedicated_replicas: []
  end

  defmodule SearchSlotRepo do
    use YtSearch.Data.RepoBase,
      primary: YtSearch.Data.SearchSlotRepo,
      read_replicas: [
        YtSearch.Data.SearchSlotRepo.Replica1,
        YtSearch.Data.SearchSlotRepo.Replica2
      ],
      dedicated_replicas: []
  end

  defmodule ThumbnailRepo do
    use YtSearch.Data.RepoBase,
      primary: YtSearch.Data.ThumbnailRepo,
      read_replicas: [
        YtSearch.Data.ThumbnailRepo.Replica1,
        YtSearch.Data.ThumbnailRepo.Replica2
      ],
      dedicated_replicas: [
        YtSearch.Data.ThumbnailRepo.JanitorReplica
      ]
  end

  defmodule ChapterRepo do
    use YtSearch.Data.RepoBase,
      primary: YtSearch.Data.ChapterRepo,
      read_replicas: [
        YtSearch.Data.ChapterRepo.Replica1,
        YtSearch.Data.ChapterRepo.Replica2
      ],
      dedicated_replicas: [
        YtSearch.Data.ChapterRepo.JanitorReplica
      ]
  end

  defmodule SponsorblockRepo do
    use YtSearch.Data.RepoBase,
      primary: YtSearch.Data.SponsorblockRepo,
      read_replicas: [
        YtSearch.Data.SponsorblockRepo.Replica1,
        YtSearch.Data.SponsorblockRepo.Replica2
      ],
      dedicated_replicas: [
        YtSearch.Data.SponsorblockRepo.JanitorReplica
      ]
  end
end
