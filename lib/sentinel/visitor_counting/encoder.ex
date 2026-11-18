defmodule Sentinel.VisitorCounting.Encoder do
  @moduledoc "JPEG annotation boundary; called only by the supervised persistence worker."

  def encode(%{frame: frame, object: object}) do
    format = %Membrane.RawVideo{
      width: frame.width,
      height: frame.height,
      framerate: {0, 1},
      pixel_format: :RGB,
      aligned: true
    }

    {payload, _} =
      Sentinel.Detection.Drawer.render(frame.payload, [object], %{
        format: format,
        objects: nil,
        overlay: nil
      })

    with {:ok, image} <- Membrane.RawVideo.payload_to_image(payload, format) do
      Image.write(image, :memory, suffix: ".jpg", quality: 85)
    end
  end
end
