defmodule FeteBot.WindowMap do
  def prepare(list) do
    {items, final_acc} =
      list
      |> Enum.flat_map_reduce(:start, fn
        # list[0]: just store item in accumulator
        x, :start -> {[], {x}}
        # list[1]: emit list[nil, 0, 1] and store list[0, 1] in accumulator
        y, {x} -> {[{nil, x, y}], {y, x}}
        # list[n]: emit list[n-2, n-1, n] and store list[n-1, n] in accumulator
        z, {y, x} -> {[{x, y, z}], {z, y}}
      end)

    case final_acc do
      # Nothing in list
      :start -> []
      # Only one item in list
      {x} -> [{nil, x, nil}]
      # Emit entry for remaining item
      {y, x} -> items ++ [{x, y, nil}]
    end
  end
end
