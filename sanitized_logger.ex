defmodule LangchainDemo.SanitizedLogger do
  require Logger

  def filter_sensitive(event) do
    config = Application.get_env(:logger, :filter_default_config)

    # Apply filters to the message
    filtered_message = Enum.reduce(config.drop, event.message, fn {_key, pattern}, msg ->
      Regex.replace(pattern, msg, "[REDACTED]")
    end)

    # Return modified event
    %{event | message: filtered_message}
  end
end
