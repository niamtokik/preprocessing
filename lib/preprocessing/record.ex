defmodule Preprocessing.Record do
  @moduledoc """
  The `Preprocessing.Record` module list available records from
  Erlang source code, usually an header (a file with `.hrl` prefix).

  It can also be used as module template to deal with
  records as Elixir Struct.

  ## Usage
  
  Firstly, create a new module for the record to import, for example,
  the record `#RSAPublicKey{}` from the `public_key` module.

  ```elixir
  defmodule MyProject.RSAPublicKey do
    use Preprocessing.Record,
      record_id: :RSAPublicKey,
      module: :public_key,
      filepath: "include/public_key.hrl"
  end
  ```

  `Preprocessing.Record` module template must be configured with the
  `record_id` of the record, its `module` and its `filepath`. The module
  MUST BE LOADED, if it's not the case, edit `mix.exs` and adds it into
  the `extra_applications` parameter. If succesful, the module should now
  be able to parse and convert records as struct.

  ```elixir
  iex> MyProject.RSAPublicKey.struct()
  %MyProject.RSAPublicKey{
    modulus: :undefined,
    publicExponent: :undefined
  }
  ```

  The keys can be listed.

  ```elixir
  iex> MyProject.RSAPublicKey.keys()
  [:modulus, :publicKeyExponent]
  ```

  And the conversion should work.

  ```elixir
  iex> MyProject.RSAPublicKey.struct() |> MyProject.RSAPublicKey.convert()
  {:ok, {:RSAPublicKey, :undefined, :undefined}}
  ```

  """

  def list_records(module, filepath, opts \\ %{}) do
    case :code.lib_dir(module) do
      {:error, reason} ->
        {:error, reason}
      path ->
        target = Path.join([path, filepath])
        list_records2(module, target, opts)
    end
  end

  defp list_records2(module, target, opts) do
    source_name = Map.get(opts, :source_name, module)
    with true <- File.exists?(target),
         {:ok, tokens} <- :epp.parse_file(target, source_name: source_name)
    do
      for {:attribute, _, :record, {record_name, _}} <- tokens, do: record_name
    else
      false -> {:error, :path};
      other -> other
    end
  end

  def extract(module, filepath, record) do
    target = Path.join([Atom.to_string(module), filepath])
    Record.extract(record, from_lib: target)
  end

  @doc false
  defmacro __using__(opts) do
    record_id = Keyword.get(opts, :record_id)
    module = Keyword.get(opts, :module)
    filepath = Keyword.get(opts, :filepath)
    fields = extract(module, filepath, record_id)
    keys = for {k, _} <- fields, do: k
    values = for {_, v} <- fields, do: v
    tuple = [:record_id] ++ values
      |> List.to_tuple()
      |> Macro.escape()
    record_size = length(fields)+1

    quote do
      import Preprocessing.Record

      defstruct unquote(fields)

      @type record_id :: atom()
      @type record_struct :: %__MODULE__{}
      @type record_tuple :: tuple()
      @type fields :: Keyword.t()
      @type keys :: [atom()]
      @type struct_or_tuple :: record_struct() | record_tuple()

      @doc """
      Returns record id.
      """
      @spec id() :: record_id()
      def id(), do: unquote(record_id)

      @doc """
      Returns tuple's fields.
      """
      @spec fields() :: fields()
      def fields(), do: unquote(fields)

      @doc """
      Returns tuple's keys.
      """
      @spec keys() :: keys()
      def keys(), do: unquote(keys)

      @doc """
      Returns the record with its default value
      """
      @spec tuple() :: record_tuple()
      def tuple(), do: unquote(tuple)

      @doc """
      Returns the current default struct.
      """
      @spec struct() :: record_struct()
      def struct(), do: %__MODULE__{}

      @doc """
      Checks if a record is a valid tuple.
      """
      @spec is_valid?(struct_or_tuple()) :: boolean()
      def is_valid?(record) do
        cond do 
          is_tuple(record) and 
            :erlang.size(record) == unquote(record_size) and 
            :erlang.element(1, record) == unquote(record_id) -> true
          true -> false
        end
      end

      @doc """
      Converts a struct to a record or a record to a tuple.
      """
      @spec convert(struct_or_tuple()) :: {:ok, struct_or_tuple()} | {:error, term()}
      def convert(struct = %__MODULE__{}) do
        map = Map.from_struct(struct)
        {:ok, Enum.reduce(fields(), [], fn ({k, _}, acc) -> 
            [Map.get(map, k)|acc]
          end)
          |> Enum.reverse()
          |> (fn(xs) -> [unquote(record_id)|xs] end).()
          |> List.to_tuple()
        }
      end
      def convert(record) when is_tuple(record) do
        if is_valid?(record) do
          record_list =
            Tuple.to_list(record)
            |> Enum.drop(1)

          {:ok, keys()
            |> Enum.zip(record_list)
            |> Enum.reduce(%__MODULE__{}, fn ({k, v}, acc) -> 
              Map.put(acc, k, v)
            end)
          }
        else
          {:error, :invalid_tuple}
        end
      end
      def convert(_), do: {:error, :invalid_term}

      @doc """
      see convert/1
      """
      @spec convert!(struct_or_tuple()) :: struct_or_tuple()
      def convert!(record) do
        case convert(record) do
          {:ok, data} -> data
          other -> throw other
        end
      end

    end
  end
end
