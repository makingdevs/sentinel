defmodule Sentinel.VisitorCounting.Snapshots do
  @moduledoc "Private flat snapshot namespace. The root must be owned exclusively by Sentinel."
  alias Sentinel.VisitorCounting

  def root, do: VisitorCounting.config(:snapshot_root, Path.expand("tmp/visitor-snapshots"))
  def new_key, do: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower) <> ".jpg"

  def path(key) when is_binary(key) do
    root = root()
    static = Path.expand("priv/static")

    with true <- Path.type(root) == :absolute,
         true <- root == Path.expand(root),
         false <- root == "/" or String.starts_with?(static, root <> "/"),
         false <- root == static or String.starts_with?(root, static <> "/"),
         true <- Regex.match?(~r/\A[0-9a-f]{64}\.jpg\z/, key),
         :ok <- no_symlinks(Path.expand(root)),
         path = Path.join(root, key),
         :ok <- no_symlinks(path) do
      {:ok, path}
    else
      _ -> {:error, :unsafe_snapshot_path}
    end
  end

  def path(_), do: {:error, :unsafe_snapshot_path}

  def write(key, jpeg) when is_binary(jpeg) do
    with {:ok, target} <- path(key),
         :ok <- File.mkdir_p(root()),
         :ok <- File.chmod(root(), 0o700) do
      temporary = target <> "." <> Base.encode16(:crypto.strong_rand_bytes(12)) <> ".tmp"

      result =
        with :ok <- File.write(temporary, jpeg, [:binary, :exclusive]),
             :ok <- File.chmod(temporary, 0o600),
             :ok <- File.rename(temporary, target) do
          :ok
        end

      File.rm(temporary)
      result
    end
  end

  def delete(key) do
    with {:ok, path} <- path(key) do
      case File.rm(path) do
        {:error, :enoent} -> :ok
        result -> result
      end
    end
  end

  defp no_symlinks(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} ->
        {:error, :symlink}

      {:error, reason} when reason != :enoent ->
        {:error, reason}

      _ ->
        parent = Path.dirname(path)
        if parent == path, do: :ok, else: no_symlinks(parent)
    end
  end
end
