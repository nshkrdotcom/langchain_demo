# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :langchain_demo,
  ecto_repos: [LangChainDemo.Repo]

# Configures the endpoint
config :langchain_demo, LangChainDemoWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: LangChainDemoWeb.ErrorHTML, json: LangChainDemoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LangChainDemo.PubSub,
  live_view: [signing_salt: "Z2RBy4NU"]

# Configure a global setting for IO.inspect limit
config :langchain_demo, :io_inspect_limit, 8 # :infinity

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :langchain_demo, LangChainDemo.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.2.7",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :langchain, :openai_key, fn -> System.fetch_env!("OPENAI_API_KEY") end

config :langchain, :google_ai_key, fn -> System.fetch_env!("GOOGLE_API_KEY") end

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Setup timezone database
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase



# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  formatter: {LangchainDemo.LoggerFormatter, :format, []}

config :logger,
  backends: [{Logger.Backends.Console, format: {LangchainDemo.LoggerFormatter, :format}}]


# Configure logger with both formatting and filtering
# config :logger, :console,
#   format: "$time $metadata[$level] $message\n",
#   metadata: [:request_id],
#   formatter: {LangchainDemo.LoggerFormatter, :format, []},
#   metadata_filter: {LangchainDemo.SanitizedLogger, :filter_sensitive}

#   config :logger,
#   backends: [{Logger.Backends.Console, format: {LangchainDemo.LoggerFormatter, :format}}],
#   filter_default_config: %{
#     keep: [],
#     drop: %{
#       # API Keys - common formats
#       api_key: ~r/[A-Za-z0-9\-_]{20,}/,
#       google_api: ~r/AIza[A-Za-z0-9\-_]{35}/,
#       gemini_key: ~r/AIzaSy[A-Za-z0-9\-_]{32}/,

#       # JWT tokens
#       jwt: ~r/eyJ[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.?[A-Za-z0-9\-_.+\/=]*/,

#       # Generic secrets and passwords
#       password: ~r/.+/,
#       secret: ~r/.+/,
#       secret_key: ~r/.+/,

#       # Database connection strings
#       database_url: ~r/postgres:\/\/.*:.*@.*/,

#       # AWS-style keys
#       aws_key: ~r/AKIA[0-9A-Z]{16}/,
#       aws_secret: ~r/[A-Za-z0-9\/+=]{40}/
#     }
#   }









# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
