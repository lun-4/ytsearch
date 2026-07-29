defmodule YtSearch.Counter do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias YtSearch.Data.CounterRepo

  @type t :: %__MODULE__{}

  @counter_ids %{global: 1, gift_drops: 2}

  @primary_key {:id, :integer, autogenerate: false}

  schema "counter" do
    field(:value, :integer, default: 0)
    timestamps()
  end

  def changeset(%__MODULE__{} = counter, params) do
    counter
    |> cast(params, [:value])
    |> validate_required([:value])
  end

  def changeset(params) do
    %__MODULE__{}
    |> changeset(params)
  end

  @spec get_counter(atom(), module()) :: t() | nil
  def get_counter(name \\ :global, repo \\ CounterRepo) do
    id = Map.fetch!(@counter_ids, name)
    query = from(c in __MODULE__, where: c.id == ^id, select: c)
    repo.one(query)
  end

  @spec increment(number(), atom()) :: t()
  def increment(delta, name \\ :global) when is_number(delta) do
    CounterRepo.transaction(
      fn ->
        counter = get_counter(name)
        int_delta = round(delta)

        if counter == nil do
          # Create initial counter
          %__MODULE__{id: Map.fetch!(@counter_ids, name), value: int_delta}
          |> CounterRepo.insert!()
        else
          new_value = counter.value + int_delta

          counter
          |> changeset(%{value: new_value})
          |> CounterRepo.update!()
        end
      end,
      mode: :immediate
    )
    |> then(fn {:ok, counter} -> counter end)
  end

  @spec get_value(atom()) :: integer()
  def get_value(name \\ :global) do
    case get_counter(name, CounterRepo.replica()) do
      nil -> 0
      counter -> counter.value
    end
  end
end
