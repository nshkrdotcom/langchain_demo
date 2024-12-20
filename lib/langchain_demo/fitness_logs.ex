defmodule LangChainDemo.FitnessLogs do
  @moduledoc """
  The FitnessLogs context.
  """

  import Ecto.Query, warn: false
  alias LangChainDemo.Repo

  alias LangChainDemo.FitnessLogs.FitnessLog

  @doc """
  Returns a list of fitness_logs for the user. Defaults to return the last 12
  days worth of entries. Can specify a different number of days, can filter LIKE
  for the activity name.

  ## Filters

  - `:days` - The number of days of history to fetch. Defaults to 12.
  - `:activity` - The activity name being queried for. Uses a LIKE query. Optional.

  ## Examples

      iex> list_fitness_logs()
      [%FitnessLog{}, ...]

  """
  def list_fitness_logs(user_id, filters \\ []) do
    try do
      days = Keyword.get(filters, :days, 12)

      # Ensure days is a non-negative integer
      days = if is_integer(days) && days >= 0, do: days, else: 12

      from_date = DateTime.utc_now() |> DateTime.to_date() |> Date.add(-days)

      query =
        from(
          f in FitnessLog,
          where: f.fitness_user_id == ^user_id,
          where: f.date >= ^from_date,
          order_by: [desc: f.date, asc: f.activity, asc: f.id]
        )

      run_query =
        case Keyword.fetch(filters, :activity) do
          {:ok, value} ->
            # Use ilike for case-insensitive matching
            from(q in query, where: ilike(q.activity, ^"%#{value}%"))

          :error ->
            query
        end

      case Repo.all(run_query) do
        {:error, reason} ->
          # Handle database errors
          IO.inspect("Database error in list_fitness_logs", limit: :infinity)
          IO.inspect(reason, label: "Reason", limit: :infinity)
          {:error, "Failed to retrieve fitness logs"}

        logs ->
          logs
      end
    catch
      e, stacktrace ->
        IO.inspect("Exception in list_fitness_logs", limit: :infinity)
        IO.inspect(e, label: "Error", limit: :infinity)
        IO.inspect(stacktrace, label: "Stacktrace", limit: :infinity)
        # Provide a more specific error message if possible
        case e do
          %ArgumentError{message: message} ->
            {:error, "Argument error while fetching fitness logs: #{message}"}
          _ ->
            {:error, "An error occurred while fetching fitness logs"}
        end
    end
  end

  @doc """
  Gets a single fitness_log.

  Raises `Ecto.NoResultsError` if the Fitness log does not exist.

  ## Examples

      iex> get_fitness_log!(123)
      %FitnessLog{}

      iex> get_fitness_log!(456)
      ** (Ecto.NoResultsError)

  """
  def get_fitness_log!(fitness_user_id, id) do
    Repo.one!(
      from(f in FitnessLog, where: f.fitness_user_id == ^fitness_user_id, where: f.id == ^id)
    )
  end

  @doc """
  Get a single fitness_log.

  Returns `{:ok, %FitnessLog{}}` when found or `{:error, "Fitness Log entry not
  found."}` when not found.
  """
  def get_fitness_log(fitness_user_id, id) do
    case Repo.one(
           from(f in FitnessLog, where: f.fitness_user_id == ^fitness_user_id, where: f.id == ^id)
         ) do
      %FitnessLog{} = log -> {:ok, log}
      nil -> {:error, "Fitness Log not found."}
    end
  end

  @doc """
  Creates a fitness_log.

  ## Examples

      iex> create_fitness_log(%{field: value})
      {:ok, %FitnessLog{}}

      iex> create_fitness_log(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_fitness_log(fitness_user_id, attrs \\ %{}) do
    fitness_user_id
    |> FitnessLog.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a fitness_log.

  ## Examples

      iex> update_fitness_log(fitness_log, %{field: new_value})
      {:ok, %FitnessLog{}}

      iex> update_fitness_log(fitness_log, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_fitness_log(%FitnessLog{} = fitness_log, attrs) do
    fitness_log
    |> FitnessLog.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a fitness_log.

  ## Examples

      iex> delete_fitness_log(fitness_log)
      {:ok, %FitnessLog{}}

      iex> delete_fitness_log(fitness_log)
      {:error, %Ecto.Changeset{}}

  """
  def delete_fitness_log(%FitnessLog{} = fitness_log) do
    Repo.delete(fitness_log)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking fitness_log changes.

  ## Examples

      iex> change_fitness_log(fitness_log)
      %Ecto.Changeset{data: %FitnessLog{}}

  """
  def change_fitness_log(%FitnessLog{} = fitness_log, attrs \\ %{}) do
    FitnessLog.changeset(fitness_log, attrs)
  end
end
