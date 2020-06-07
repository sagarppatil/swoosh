if Code.ensure_loaded?(Plug) do
  defmodule Plug.Swoosh.AcceptContentType do
    import Plug.Conn

    @moduledoc """
    Plug that accepts content types supplied

    It receives a connection, a list of formats that the server
    is capable of rendering and then proceeds to perform content
    negotiation based on the request information. If the client
    accepts any of the given formats, the request proceeds.

    If the request contains a "_format" parameter, it is
    considered to be the format desired by the client. If no
    "_format" parameter is available, this function will parse
    the "accept" header and find a matching format accordingly.
    This function is useful when you may want to serve different
    content-types (such as JSON and HTML) from the same routes.

    It is important to notice that browsers have historically
    sent bad accept headers. For this reason, this function will
    default to "html" format whenever:
      * the accept header specified more than one media type preceded
        or followed by the wildcard media type "`*/*`"

    This function raises `Plug.Swoosh.NotAcceptableError`, which is rendered
    with status 406, whenever the server cannot serve a response in any
    of the formats expected by the client.

    ## Examples
    `accepts/2` can be invoked as a function:
      iex> accepts(conn, ["html", "json"])
    or used as a plug:
      plug :accepts, ["html", "json"]
      plug :accepts, ~w(html json)
    """

    def accepts(conn, [_ | _] = accepted) do
      case Map.fetch(conn.params, "_format") do
        {:ok, format} ->
          handle_params_accept(conn, format, accepted)

        :error ->
          handle_header_accept(
            conn,
            get_req_header(conn, "accept"),
            accepted
          )
      end
    end

    defp handle_params_accept(conn, format, accepted) do
      if format in accepted do
        put_format(conn, format)
      else
        raise Plug.Swoosh.NotAcceptableError,
          message:
            "unknown format #{inspect(format)}, expected one of #{
              inspect(accepted)
            }",
          accepts: accepted
      end
    end

    defp handle_header_accept(conn, header, [first | _])
         when header == [] or header == ["*/*"] do
      put_format(conn, first)
    end

    defp handle_header_accept(conn, [header | _], accepted) do
      parse_header_accept(conn, String.split(header, ","), [], accepted)
    end

    defp parse_header_accept(conn, [h | t], acc, accepted) do
      case Plug.Conn.Utils.media_type(h) do
        {:ok, type, subtype, args} ->
          exts = parse_exts(type, subtype)
          q = parse_q(args)

          if format = q === 1.0 && find_format(exts, accepted) do
            put_format(conn, format)
          else
            parse_header_accept(conn, t, [{-q, h, exts} | acc], accepted)
          end

        :error ->
          parse_header_accept(conn, t, acc, accepted)
      end
    end

    defp parse_header_accept(conn, [], acc, accepted) do
      acc
      |> Enum.sort()
      |> Enum.find_value(&parse_header_accept(conn, &1, accepted))
      |> Kernel.||(refuse(conn, acc, accepted))
    end

    defp parse_header_accept(conn, {_, _, exts}, accepted) do
      if format = find_format(exts, accepted) do
        put_format(conn, format)
      end
    end

    defp parse_q(args) do
      case Map.fetch(args, "q") do
        {:ok, float} ->
          case Float.parse(float) do
            {float, _} -> float
            :error -> 1.0
          end

        :error ->
          1.0
      end
    end

    defp parse_exts("*", "*"), do: "*/*"
    defp parse_exts(type, "*"), do: type
    defp parse_exts(type, subtype), do: MIME.extensions(type <> "/" <> subtype)

    defp find_format("*/*", accepted), do: Enum.fetch!(accepted, 0)

    defp find_format(exts, accepted) when is_list(exts),
      do: Enum.find(exts, &(&1 in accepted))

    defp find_format(_type_range, []), do: nil

    defp find_format(type_range, [h | t]) do
      mime_type = MIME.type(h)

      case Plug.Conn.Utils.media_type(mime_type) do
        {:ok, accepted_type, _subtype, _args}
        when type_range === accepted_type ->
          h

        _ ->
          find_format(type_range, t)
      end
    end

    @spec refuse(term(), [tuple], [binary]) :: no_return()
    defp refuse(_conn, given, accepted) do
      raise Plug.Swoosh.NotAcceptableError,
        accepts: accepted,
        message: """
        no supported media type in accept header.
        Expected one of #{inspect(accepted)} but got the following formats:
          * #{
          Enum.map_join(given, "\n  ", fn {_, header, exts} ->
            inspect(header) <> " with extensions: " <> inspect(exts)
          end)
        }
        To accept custom formats, register them under the :mime library
        in your config/config.exs file:
            config :mime, :types, %{
              "application/xml" => ["xml"]
            }
        And then run `mix deps.clean --build mime` to force it to be recompiled.
        """
    end

    def get_format(conn) do
      conn.private[:swoosh_format] || conn.params["_format"]
    end

    defp put_format(conn, format) do
      put_private(conn, :swoosh_format, format)
    end
  end
end
