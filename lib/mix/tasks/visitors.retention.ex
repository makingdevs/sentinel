defmodule Mix.Tasks.Visitors.Retention do
  @moduledoc "Reports expired crossings (default dry run). Use --apply to delete a batch of up to 100 and --days N to override retention."
  @shortdoc "Inspect or apply visitor snapshot retention"
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, invalid} = OptionParser.parse(args, strict: [apply: :boolean, days: :integer])
    if invalid != [], do: Mix.raise("Use --apply and/or --days N")
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Sentinel.Repo, fn _ ->
        options = [dry_run: not Keyword.get(opts, :apply, false)]
        options = if opts[:days], do: Keyword.put(options, :days, opts[:days]), else: options
        Mix.shell().info(inspect(Sentinel.VisitorCounting.Retention.prune(options), pretty: true))
        Mix.shell().info("Unreferenced JPEGs (read-only, may include in-flight files):")
        Mix.shell().info(inspect(Sentinel.VisitorCounting.Retention.orphans()))
      end)
  end
end
