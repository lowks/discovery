defmodule Discovery.Directory do
  @moduledoc """
  A registered process that contains the state of known nodes and the services
  that they provide.
  """

  use GenServer
  @name Discovery.Directory

  def start_link do
    Agent.start_link(fn -> %{nodes: %{}, services: %{}} end, name: @name)
  end

  @doc """
  Add a node and the service it provides to the directory.
  """
  @spec add(atom, binary) :: :ok
  def add(node, service) when is_atom(node) and is_binary(service) do
    Agent.update(@name, fn(%{nodes: nodes, services: services} = state) ->
      case Discovery.Ring.add(service, node) do
        :ok ->
          case Dict.fetch(services, service) do
            :error ->
              new_services = Dict.put(services, service, HashSet.new |> Set.put(node))
            {:ok, nodes} ->
              new_services = Dict.put(services, service, Set.put(nodes, node))
          end

          case Dict.fetch(nodes, node) do
            :error ->
              new_nodes = Dict.put(nodes, node, HashSet.new |> Set.put(service))
            {:ok, node_services} ->
              new_nodes = Dict.put(nodes, node, Set.put(node_services, service))
          end

          %{state | nodes: new_nodes, services: new_services}
        _ ->
          state
      end
    end)
  end

  @doc false
  def clear do
    Agent.update(@name, fn(%{nodes: nodes}) ->
      Map.keys(nodes) |> Enum.each(&Discovery.Ring.drop/1)
      %{nodes: %{}, services: %{}}
    end)
  end

  @doc """
  Drop a node from the directory.
  """
  @spec drop(atom) :: :ok
  def drop(node) when is_atom(node) do
    Agent.update(@name, fn(%{nodes: nodes, services: services} = state) ->
      case Discovery.Ring.drop(Map.keys(services), node) do
        :ok ->
          case Dict.pop(nodes, node) do
            {nil, new_nodes} ->
              new_nodes    = new_nodes
              new_services = services
            {_, new_nodes} ->
              new_nodes    = new_nodes
              new_services = Enum.reduce(services, %{}, fn({key, value}, acc) ->
                new_set = Set.delete(value, node)
                case Enum.empty?(new_set) do
                  true ->
                    :ok = Discovery.Ring.destroy(key)
                    acc
                  false ->
                    Map.put(acc, key, new_set)
                end
              end)
          end

          %{state | nodes: new_nodes, services: new_services}
        _ ->
          state
      end
    end)
  end

  @doc """
  Find a node running service hashed by hash.
  """
  @spec find(binary, binary) :: {:ok, node} | {:error, term}
  def find(service, hash) do
    case Discovery.Ring.find(service, hash) do
      {:error, _} ->
        {:error, :no_servers}
      {:ok, _} = result ->
        result
    end
  end

  @doc """
  Checks if node exists within the Directory.
  """
  @spec has_node?(atom) :: boolean
  def has_node?(node) when is_atom(node) do
    Agent.get(@name, fn(%{nodes: nodes}) ->
      Map.has_key?(nodes, node)
    end)
  end

  @doc """
  List all nodes and the services they provide.
  """
  @spec nodes :: Set.t
  def nodes do
    Agent.get(@name, fn(%{nodes: nodes}) -> nodes end)
  end

  @doc """
  List all nodes which provide the given service.
  """
  @spec nodes(binary) :: list
  def nodes(service) when is_binary(service) do
    Agent.get(@name, fn(%{services: services}) ->
      case Map.fetch(services, service) do
        :error ->
          []
        {:ok, nodes} ->
          Set.to_list(nodes)
      end
    end)
  end

  @doc """
  List all services and the nodes which provide them.
  """
  @spec services :: Set.t
  def services do
    Agent.get(@name, fn(%{services: services}) -> services end)
  end
end