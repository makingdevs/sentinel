defmodule SentinelWeb.PageControllerTest do
  use SentinelWeb.ConnCase

  for {name, ip, local?} <- [
        {"IPv4 local", {127, 0, 0, 1}, true},
        {"IPv6 local", {0, 0, 0, 0, 0, 0, 0, 1}, true},
        {"remote", {192, 168, 1, 20}, false}
      ] do
    test "home navigation for #{name}", %{conn: conn} do
      conn = get(%{conn | remote_ip: unquote(Macro.escape(ip))}, ~p"/")
      document = conn |> html_response(200) |> LazyHTML.from_document()

      assert LazyHTML.query(document, "#home-heading") |> Enum.count() == 1
      assert LazyHTML.query(document, "#home-cameras[href='/cameras']") |> Enum.count() == 1

      for selector <- [
            "#home-history[href='/visitors']",
            "#home-catalog[href='/cameras/catalog']"
          ] do
        assert LazyHTML.query(document, selector) |> Enum.count() ==
                 if(unquote(local?), do: 1, else: 0)
      end

      assert LazyHTML.query(document, "html[lang='es'][data-theme='dark']") |> Enum.count() == 1
      assert LazyHTML.query(document, "main main") |> Enum.empty?()
      assert LazyHTML.query(document, "script:not([src])") |> Enum.empty?()
      assert LazyHTML.query(document, "[data-phx-theme]") |> Enum.empty?()
    end
  end
end
