defmodule Explorer.Chain.Import.Runner.CeloValidators do
  @moduledoc """
  Bulk imports Celo validators to the DB table.
  """

  require Ecto.Query

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.{CeloValidator, Import}
  alias Explorer.Chain.Import.Runner.Util

  import Ecto.Query, only: [from: 2]

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [CeloValidator.t()]

  @impl Import.Runner
  def ecto_schema_module, do: CeloValidator

  @impl Import.Runner
  def option_key, do: :celo_validators

  @impl Import.Runner
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Import.Runner
  def run(multi, changes_list, options) do
    insert_options = Util.make_insert_options(option_key(), @timeout, options)

    # Enforce ShareLocks tables order (see docs: sharelocks.md)
    multi
    |> Multi.run(:acquire_all_celo_validators, fn repo, _ ->
      acquire_all_celo_validators(repo)
    end)
    |> Multi.run(:insert_celo_validators, fn repo, _ ->
      insert(repo, changes_list, insert_options)
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  defp acquire_all_celo_validators(repo) do
    query =
      from(
        account in CeloValidator,
        # Enforce ShareLocks order (see docs: sharelocks.md)
        order_by: account.address,
        lock: "FOR UPDATE"
      )

    accounts = repo.all(query)

    {:ok, accounts}
  end

  @spec insert(Repo.t(), [map()], Util.insert_options()) :: {:ok, [CeloValidator.t()]} | {:error, [Changeset.t()]}
  defp insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    # Enforce ShareLocks order (see docs: sharelocks.md)
    uniq_changes_list =
      changes_list
      |> Enum.sort_by(& &1.address)
      |> Enum.dedup_by(& &1.address)

    {:ok, _} =
      Import.insert_changes_list(
        repo,
        uniq_changes_list,
        conflict_target: :address,
        on_conflict: on_conflict,
        for: CeloValidator,
        returning: [:address],
        timeout: timeout,
        timestamps: timestamps
      )
  end

  defp default_on_conflict do
    from(
      account in CeloValidator,
      update: [
        set: [
          group_address_hash: fragment("EXCLUDED.group_address_hash"),
          member: fragment("EXCLUDED.member"),
          score: fragment("EXCLUDED.score"),
          signer_address_hash: fragment("EXCLUDED.signer_address_hash"),
          inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", account.inserted_at),
          updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", account.updated_at)
        ]
      ]
    )
  end
end
