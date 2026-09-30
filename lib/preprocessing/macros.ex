defmodule Preprocessing.Macros do
  @moduledoc """
  `Processing.Macros` module extract Erlang macro defined by
  the attribute `-define()` usually found in headers. It can
  be used as a module template.
  """

  @doc """
  Returns the list of available macros from an Erlang module
  header. The module MUST BE LOADED before executing this
  function.
  """
  @spec definitions(atom(), String.t()) :: {:ok, Keyword.t()}
  def definitions(module, filepath) do
    with {:ok, pid} <- open_file(module, filepath),
      :ok <- definitions_loop(pid),
      {:ok, macros} <- definitions_macros(pid)
    do
      convert_macros(macros, [])
    end
  end

  # a wrapper around :code.lib_dir/1 and :epp.open/2. It check
  # if the requested file exist and if it's the case, it
  # returns an epp server process.
  @spec open_file(atom(), String.t()) :: {:ok, pid()}
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

  # read the whole file to parse until eof.
  @spec definitions_loop(pid()) :: :ok
  defp definitions_loop(pid) do
    msg = :epp.parse_erl_form(pid)
    case msg do
      {:eof, _} ->
        :ok
      _ ->
        definitions_loop(pid)
    end
  end

  # extract the macros from the epp server process
  # and convert them to be compatible with this module.
  @spec definitions_macros(pid()) :: {:ok, Keyword.t()}
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

  # convert all supporter macro. At this time, some
  # of them are ignored (dynamic macro with arity >0)
  defp convert_macros([], buffer) do
    {:ok,
      buffer
      |> Enum.filter(fn({_, v}) ->
        if v==:ignored do
          false
        else
          true
        end
     end)
    }
  end
  defp convert_macros([macro={{:atom, name}, value}|rest], buffer) do
    with {:ok, term} <- convert_macro_value(value) do
      convert_macros(rest, [{name, term}|buffer])
    else
      error -> {:error, error, macro}
    end
  end

  # convert a macro value into Erlang term compatible with Elixir.
  # Only static macros are currently imported.
  defp convert_macro_value([none: {:none, value}]) do
    with {:ok, term} <- :erl_parse.parse_term(value ++ [{:dot, 1131}]) do
      {:ok, term}
    end
  end
  defp convert_macro_value(_), do: {:ok, :ignored}

  # return the extracted macros, convert them to a Map
  # and escape them for the template.
  defp escape_keys(module, filepath) do
    with {:ok, defs} <- definitions(module, filepath) do
      defs
      |> :maps.from_list()
      |> Macro.escape()
    end
  end

  # return only the keys from the macros.
  defp macro_keys(module, filepath) do
    with {:ok, defs} <- definitions(module, filepath) do
      defs
      |> Enum.map(fn({k,_}) -> k end)
      |> Macro.escape()
    end
  end

  # returns only the macro values.
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
    def_keys = escape_keys(module, filepath)

    quote do
      import Preprocessing.Macros

      @doc """
      returns the whole key/value macros.
      """
      @spec macros() :: Map.t()
      def macros(), do: unquote(def_keys)

      @doc """
      Returns key's value or value's key.
      """
      @spec macro(atom()) :: term() | nil
      def macro(index), do: Map.get(unquote(def_keys), index)

      @doc """
      Returns the list of all keys.
      """
      @spec macro_keys() :: [atom()]
      def macro_keys(), do: unquote(macro_keys(module, filepath))

      @doc """
      Returns the list of all values.
      """
      @spec macro_values() :: [term()]
      def macro_values(), do: unquote(macro_values(module, filepath))

      @doc """
      An helper function to filter the macros, a simple wrapper
      around `Map.filter/1`.
      """
      @spec macro_filter(function()) :: Map.t()
      def macro_filter(fun) do
        unquote(def_keys)
        |> Map.filter(fun)
      end
    end
  end
end
