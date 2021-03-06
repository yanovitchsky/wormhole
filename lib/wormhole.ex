defmodule Wormhole do
  use Application

  alias Wormhole.Defaults

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Task.Supervisor, [[name: :wormhole_task_supervisor]]),
    ]

    opts = [strategy: :one_for_one, name: Wormhole.Supervisor]
    Supervisor.start_link(children, opts)
  end


  #################  API  #################

  @description """
  Invokes `callback` in separate process and
  waits for message from callback process containing callback return value
  if finished successfully or
  error reason if callback process failed for any reason.

  If `callback` execution is not finished within specified timeout,
  kills `callback` process and returns error.
  Default timeout is #{Defaults.timeout_ms} milliseconds.
  User can specify `timeout_ms` in `options` keyword list.

  By default there is no retry, but user can specify
  `retry_count` and `backoff_ms` in `options`.
  Default `backoff_ms` is #{Defaults.backoff_ms} milliseconds.
  """

  @doc """
  #{@description}

  Examples:
      iex> capture(fn-> :a end)
      {:ok, :a}

      iex> capture(fn-> raise "Something happened" end) |> elem(0)
      :error

      iex> capture(fn-> throw "Something happened" end) |> elem(0)
      :error

      iex> capture(fn-> exit :foo end)
      {:error, {:shutdown, :foo}}

      iex> capture(fn-> Process.exit(self, :foo) end)
      {:error, :foo}

      iex> capture(fn-> :timer.sleep 20 end, timeout_ms: 50)
      {:ok, :ok}

      iex> capture(fn-> :timer.sleep :infinity end, timeout_ms: 50)
      {:error, {:timeout, 50}}

      iex> capture(fn-> exit :foo end, [retry_count: 3, backoff_ms: 100])
      {:error, {:shutdown, :foo}}
  """
  def capture(callback, options \\ [])
  def capture(callback, options) do
    Wormhole.Retry.exec(callback, options)
    |> logger(callback)
  end


  @doc """
  #{@description}

  Examples:
      iex> capture(Enum, :count, [[]])
      {:ok, 0}

      iex> capture(Enum, :count, [:foo]) |> elem(0)
      :error

      iex> capture(:timer, :sleep, [20], timeout_ms: 50)
      {:ok, :ok}

      iex> capture(:timer, :sleep, [:infinity], timeout_ms: 50)
      {:error, {:timeout, 50}}

    iex> capture(Kernel, :exit, [:foos], [retry_count: 3, backoff_ms: 100])
    {:error, {:shutdown, :foos}}
  """
  def capture(module, function, args, options \\ [])
  def capture(module, function, args, options) do
    Wormhole.Retry.exec(fn-> apply(module, function, args) end, options)
    |> logger({module, function, args})
  end


  defp logger(response = {:ok, _},         _callback), do: response
  defp logger(response = {:error, reason}, callback)   do
    require Logger
    Logger.warn "#{__MODULE__}{#{inspect self}}:: callback: #{inspect callback}; reason: #{inspect reason}";

    response
  end
end
