defmodule Plug.Swoosh.NotAcceptableError do
  @moduledoc """
  Raised when one of the `accept*` headers is not accepted by the server.

  If you are seeing this error, you should check if you are listing
  the desired formats in your `:accepts` plug or if you are setting
  the proper accept header in the client. The exception contains the
  acceptable mime types in the `accepts` field.
  """
  defexception message: nil, accepts: [], plug_status: 406
end
