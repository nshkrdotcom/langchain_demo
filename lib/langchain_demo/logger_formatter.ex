defmodule LangchainDemo.LoggerFormatter do
  def format(_level, message, timestamp, metadata) do
    formatted_timestamp =
      case timestamp do
        {{year, month, day}, {hour, minute, second, _microsecond}} ->
          ~s[#{year}-#{month}-#{day} #{hour}:#{minute}:#{second}]

        _ ->
          "Invalid Timestamp"
      end

    message =
      case metadata[:exception] do
        {exception, stacktrace} ->
          formatted_stacktrace =
            stacktrace
            |> Exception.format_stacktrace()
            |> Enum.join("\n    ") # Indent stack trace lines

          """
          #{message} (#{exception})
              #{formatted_stacktrace}
          """

        _ ->
          message
      end

    "#{formatted_timestamp} #{message}\n"
  end
end
