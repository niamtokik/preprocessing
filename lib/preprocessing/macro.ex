defmodule Preprocessing.Macro do
  @moduledoc """
  """

  def definitions(module, filepath) do
    with {:ok, pid} <- open_file(module, filepath),
      :ok <- definitions_loop(pid),
      {:ok, macros} <- definitions_macros(pid)
    do
      convert_macros(macros, [])
    end
  end

  defp open_file(module, filepath) do
    case :code.lib_dir(module) do
      {:error, reason} ->
        {:error, reason}
      path ->
        Path.join([path, filepath])
          |> String.to_charlist()
          |> :epp.open([], [])
    end
  end

  defp definitions_loop(pid) do
    msg = :epp.parse_erl_form(pid)
    case msg do
      {:eof, _} ->
        :ok
      _ ->
        definitions_loop(pid)
    end
  end

  defp definitions_macros(pid) do
    send(pid, {:epp_request, self(), :macro_defs})
    receive do
      {:epp_reply, pid, macros} ->
        :epp.close(pid)
        {:ok, macros}
      msg ->
        :epp.close(pid)
        {:error, msg}
      after
        10000 ->
          :epp.close(pid)
          {:error, :timeout}
      end
  end

  defp convert_macros([], buffer) do 
    {:ok, 
      buffer
        |> Enum.filter(fn({_, v}) -> if v==:ignored do false else true end end)
    }
  end
  defp convert_macros([macro={{:atom, name}, value}|rest], buffer) do
    with {:ok, term} <- convert_macro_value(value) do
      convert_macros(rest, [{name, term}|buffer])
    else
      error -> {:error, error, macro}
    end
  end

  defp convert_macro_value([none: {:none, value}]) do
    with {:ok, term} <- :erl_parse.parse_term(value ++ [{:dot, 1131}]) do
      {:ok, term}
    end
  end
  defp convert_macro_value(_), do: {:ok, :ignored}

  defp escape(module, filepath) do
    with {:ok, defs} <- definitions(module, filepath) do
      key_value = defs
      value_key = defs
        |> Enum.map(fn({k,v}) -> {v,k} end)

      as_map = Enum.concat(key_value, value_key)
        |> :maps.from_list()
      Macro.escape(as_map)
    end
  end

  defp macro_keys(module, filepath) do
    with {:ok, defs} <- definitions(module, filepath) do
      defs
      |> Enum.map(fn({k,_}) -> k end)
      |> Macro.escape()
    end
  end

  # returns only the macro values
  defp macro_values(module, filepath) do 
    with {:ok, defs} <- definitions(module, filepath) do
      defs
      |> Enum.map(fn({_,v}) -> v end)
      |> Macro.escape()
    end
  end

  @doc false
  defmacro __using__(opts) do
    module = Keyword.get(opts, :module)
    filepath = Keyword.get(opts, :filepath)
    defs = escape(module, filepath)

    quote do
      import Preprocessing.Macro

      @doc """
      returns the whole key/value macros.
      """
      def macros(), do: unquote(defs)

      @doc """
      Returns key's value or value's key.
      """
      def macro(index) do
        Map.get(unquote(defs), index)
      end

      @doc """
      Returns the list of all keys.
      """
      def macro_keys(), do: unquote(macro_keys(module, filepath))

      @doc """
      Returns the list of all values.
      """
      def macro_values(), do: unquote(macro_values(module, filepath))

      @doc """
      A function helper to search inside the macros keys.
      """
      def search_keys(regexp) do
        macro_keys()
        |> Enum.map(&Atom.to_string/1)
        |> Enum.filter(fn(k) ->
          cond do
            Regex.match?(regexp, k) -> true
            true -> false
          end
        end)
      end
    end
  end
end
