defmodule Sentinel.VisitorCounting.ContextTest do
  use Sentinel.DataCase, async: false
  import Sentinel.MonitoringFixtures
  setup :camera_catalog_fixture_setup

  defp camera_catalog_fixture_setup(_context), do: camera_catalog_fixture()

  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.{Persistence, Retention, Snapshots}

  setup do
    original = Application.get_env(:sentinel, :visitor_counting, [])
    root = Path.join("/private/tmp", "visitor-#{System.unique_integer([:positive])}")
    Application.put_env(:sentinel, :visitor_counting, snapshot_root: root)

    on_exit(fn ->
      Application.put_env(:sentinel, :visitor_counting, original)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "validates camera, normalized geometry and versions settings" do
    assert {:error, _} = VisitorCounting.configure_rule("missing", %{})
    assert {:error, _} = VisitorCounting.configure_rule("division-1", %{x1: -1})
    assert {:error, _} = VisitorCounting.configure_rule("division-1", %{x1: 0.5, x2: 0.5})
    assert {:ok, rule} = VisitorCounting.configure_rule("division-1", %{})
    refute rule.enabled
    assert {:ok, next} = VisitorCounting.configure_rule("division-1", %{confidence: 0.7})
    assert next.revision == rule.revision + 1
    assert length(VisitorCounting.list_rules()) == 1
  end

  test "idempotent snapshot, filters and totals; invalid insert compensates file", %{root: root} do
    attrs = attrs("one")
    {:ok, jpeg} = Image.new!(32, 32, color: :black) |> Image.write(:memory, suffix: ".jpg")
    assert {:ok, first, :inserted} = Persistence.save(attrs, jpeg)
    assert {:ok, second, :existing} = Persistence.save(attrs, "ignored")
    assert first.id == second.id
    assert {:ok, path} = Snapshots.path(first.snapshot_key)
    assert File.read!(path) == jpeg
    assert {:ok, image} = Image.open(path)
    assert Image.width(image) == 32
    assert length(File.ls!(root)) == 1

    assert {:error, _} =
             Persistence.save(%{attrs | dedupe_key: "invalid", direction: "invalid"}, "jpeg")

    assert length(File.ls!(root)) == 1
    assert %{entry: 1, exit: 0} = VisitorCounting.totals(%{"camera_id" => "division-1"})
    assert [] = VisitorCounting.list_events(%{"direction" => "exit"})
    assert [] = VisitorCounting.list_events(%{"from" => DateTime.add(attrs.crossed_at, 1)})
    assert [] = VisitorCounting.list_events(%{}, 2)
  end

  test "snapshot provenance round trips without inventing historical metadata" do
    assert {:ok, historical, :inserted} = Persistence.save(attrs("historical"), "jpeg")
    assert historical.snapshot_quality == nil
    assert historical.snapshot_received_at == nil

    for {quality, reason} <- [{"primary", nil}, {"secondary", "stale"}] do
      metadata = %{
        snapshot_quality: quality,
        snapshot_received_at: DateTime.utc_now(),
        snapshot_width: 1920,
        snapshot_height: 1080,
        snapshot_fallback_reason: reason,
        tracking_width: 640,
        tracking_height: 360
      }

      assert {:ok, event, :inserted} =
               Persistence.save(Map.merge(attrs(quality), metadata), "jpeg")

      stored = VisitorCounting.get_event(event.id)
      assert Map.take(stored, Map.keys(metadata)) == metadata
    end

    for invalid <- [
          %{snapshot_quality: "other"},
          %{snapshot_width: 0},
          %{snapshot_quality: "secondary"},
          %{snapshot_fallback_reason: "unknown"}
        ] do
      refute Sentinel.VisitorCounting.PassageEvent.changeset(Map.merge(attrs("invalid"), invalid)).valid?
    end
  end

  test "concurrent retries return one row and one image", %{root: root} do
    supervisor = start_supervised!(Task.Supervisor)

    tasks =
      for _ <- 1..8 do
        Task.Supervisor.async_nolink(supervisor, fn -> Persistence.save(attrs("race"), "jpeg") end)
      end

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.all?(results, &match?({:ok, _, _}, &1))
    assert length(Enum.uniq(Enum.map(results, fn {:ok, event, _} -> event.id end))) == 1
    assert Enum.count(results, &match?({:ok, _, :inserted}, &1)) == 1
    assert length(File.ls!(root)) == 1
  end

  test "rejects traversal, public roots and symlink destinations", %{root: root} do
    assert {:error, _} = Snapshots.path("../secret")
    key = Snapshots.new_key()
    File.mkdir_p!(root)
    File.ln_s!("/etc/passwd", Path.join(root, key))
    assert {:error, _} = Snapshots.path(key)

    Application.put_env(:sentinel, :visitor_counting,
      snapshot_root: Path.expand("priv/static/private")
    )

    assert {:error, _} = Snapshots.path(Snapshots.new_key())

    for unsafe <- ["/", Path.expand("."), Path.expand("tmp") <> "/../priv/static", "relative"] do
      Application.put_env(:sentinel, :visitor_counting, snapshot_root: unsafe)
      assert {:error, _} = Snapshots.path(Snapshots.new_key())
    end
  end

  defp attrs(key) do
    %{
      camera_id: "division-1",
      rule_revision: 1,
      crossed_at: DateTime.utc_now(),
      direction: "entry",
      tracking_session_id: "session",
      track_id: 1,
      crossing_number: 1,
      confidence: 0.9,
      bbox: %{cx: 20, cy: 20, w: 10, h: 10},
      dedupe_key: key
    }
  end

  test "retention dry-run preserves files, application deletes expired rows/files and reports orphans" do
    attrs = attrs("expired")
    {:ok, event, :inserted} = Persistence.save(attrs, "jpeg")
    orphan = Snapshots.new_key()
    assert :ok = Snapshots.write(orphan, "orphan")
    assert Retention.orphans() == [orphan]
    now = DateTime.add(attrs.crossed_at, 2 * 86_400)
    assert %{dry_run: true, deleted: 0, candidates: [_]} = Retention.prune(now: now, days: 1)
    assert VisitorCounting.get_event(event.id)
    assert %{deleted: 1, file_errors: []} = Retention.prune(now: now, days: 1, dry_run: false)
    refute VisitorCounting.get_event(event.id)
    {:ok, path} = Snapshots.path(event.snapshot_key)
    refute File.exists?(path)
    assert Retention.orphans() == [orphan]
    assert_raise ArgumentError, fn -> Retention.prune(days: 0) end
  end
end
