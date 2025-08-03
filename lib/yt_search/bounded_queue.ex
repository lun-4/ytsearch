defmodule YtSearch.BoundedQueue do
  def new(max_size), do: {:queue.new(), max_size, 0}

  def enqueue({queue, max_size, current_size}, item) do
    queue = :queue.in(item, queue)

    if current_size >= max_size do
      # Remove oldest item when at capacity
      {{:value, _removed}, queue} = :queue.out(queue)
      {queue, max_size, current_size}
    else
      {queue, max_size, current_size + 1}
    end
  end

  def dequeue({queue, max_size, current_size}) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        {{:ok, item}, {new_queue, max_size, current_size - 1}}

      {:empty, queue} ->
        {:empty, {queue, max_size, current_size}}
    end
  end

  def to_list({queue, _max_size, _current_size}), do: :queue.to_list(queue)
end
