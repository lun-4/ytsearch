defmodule YtSearch.Counter do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias YtSearch.Data.CounterRepo

  @type t :: %__MODULE__{}

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

  @spec get_counter() :: t() | nil
  def get_counter() do
    query = from(c in __MODULE__, where: c.id == 1, select: c)
    CounterRepo.one(query)
  end

  @spec increment(number()) :: t()
  def increment(delta) when is_number(delta) do
    CounterRepo.transaction(
      fn ->
        counter = get_counter()
        int_delta = round(delta)

        if counter == nil do
          # Create initial counter
          %__MODULE__{id: 1, value: int_delta}
          |> CounterRepo.insert!()
        else
          # Update existing counter with bounds 0-1000
          new_value = min(1000, max(0, counter.value + int_delta))

          counter
          |> changeset(%{value: new_value})
          |> CounterRepo.update!()
        end
      end,
      mode: :immediate
    )
    |> then(fn {:ok, counter} -> counter end)
  end

  @spec get_value() :: integer()
  def get_value() do
    case get_counter() do
      nil -> 0
      counter -> counter.value
    end
  end
end
