case Sentinel.Monitoring.SeedImporter.import_file(System.get_env("CAMERA_RTSP_SOURCES_FILE")) do
  {:ok, %{cameras: cameras, sources: sources}} ->
    IO.puts("Seeded #{cameras} cameras and #{sources} sources")

  {:error, message} ->
    raise message
end
