defmodule LangChainDemoWeb.AgentChatLive.Agent.FitnessLogsTool do
  @moduledoc """
  Defines a set of LLM tools for working with the FitnessLogs linked to the user's account..
  """
  require Logger
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChainDemo.FitnessLogs

  @doc """
  Return the functions used for operating on a user's FitnessLogs.
  """
  @spec new_functions!() :: [Function.t()]
  def new_functions!() do
    [
      new_get_fitness_logs!(),
      new_create_fitness_log!()
    ]
  end

  @doc """
  Defines the "get_fitness_logs" function.
  """
  @spec new_get_fitness_logs!() :: Function.t() | no_return()
  def new_get_fitness_logs!() do
    Function.new!(%{
      name: "get_fitness_logs",
      display_text: "Request fitness logs",
      description: "Search for and return the user's past fitness workout logs as a JSON array.",
      parameters: [
        FunctionParam.new!(%{
          name: "days",
          type: :integer,
          description: "The number of days of history to return from the search. Defaults to 12"
        }),
        FunctionParam.new!(%{
          name: "activity",
          type: :string,
          description:
            "The name of the activity being search for. Searches for one activity at a time, but supports partial matches. An activity of \"bench\" returns both Incline Bench and Bench Press"
        })
      ],
      function: &execute_get_fitness_logs/2
    })
  end

  @spec execute_get_fitness_logs(args :: %{String.t() => any()}, context :: map()) ::
    {:ok, String.t()} | {:error, String.t()}
  def execute_get_fitness_logs(%{} = args, %{live_view_pid: pid, current_user: user} = _context) do
    # Use the context for the current_user
    days = Map.get(args, "days", nil)
    activity = Map.get(args, "activity", nil)

    # Basic validation for days (should be a non-negative integer)
    days = if is_integer(days) && days >= 0, do: days, else: nil

    filters =
    [
    if days do
      {:days, days}
    else
      nil
    end,
    if activity do
      {:activity, "%#{activity}%"}
    else
      nil
    end
    ]
    |> Enum.reject(&is_nil(&1))

    send(pid, {:function_run, "Retrieving fitness history."})

      try do
      result = FitnessLogs.list_fitness_logs(user.id, filters)

      case result do
      {:error, reason} ->
        IO.inspect("Error in FitnessLogs.list_fitness_logs", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
        IO.inspect(reason, label: "Reason", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
        {:error, reason} # Now returns the error reason from list_fitness_logs

      logs ->
        case Jason.encode(logs) do
          {:ok, json_string} ->
            {:ok, json_string}

          {:error, reason} ->
            # Handle Jason encoding errors
            IO.inspect("Error encoding logs to JSON", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
            IO.inspect(logs, label: "Logs", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
            IO.inspect(reason, label: "Encoding Reason", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
            {:error, "An error occurred while encoding the fitness logs."}
        end
      end
    catch
      e, stacktrace ->
      IO.inspect("Exception in execute_get_fitness_logs", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
      IO.inspect(e, label: "Error", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
      IO.inspect(stacktrace, label: "Stacktrace", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
      {:error, "An unexpected error occurred while retrieving fitness logs."}
      end
  end

  @doc """
  Defines the "create_fitness_log" function.
  """
  @spec new_create_fitness_log!() :: Function.t() | no_return()
  def new_create_fitness_log!() do
    Function.new!(%{
      name: "create_fitness_log",
      description: "Create a new fitness log entry for the user.",
      display_text: "Record fitness log entry",
      parameters: [
        FunctionParam.new!(%{
          name: "date",
          type: :string,
          description: "The date the activity was performed as a string in the format YYYY-MM-DD"
        }),
        FunctionParam.new!(%{
          name: "activity",
          type: :string,
          description:
            "The name of the activity. Ex: Running, Elliptical, Bench Press, Push Ups, Bent-Over Rows, etc"
        }),
        FunctionParam.new!(%{
          name: "amount",
          type: :integer,
          description:
            "Either the duration in time, a distance traveled, the number of times an activity was performed (like push-ups), or the weight used (like \"25\" for 25 lbs)"
        }),
        FunctionParam.new!(%{
          name: "units",
          type: :string,
          description: "One word unit for the amount. Ex: lbs, minutes, miles, count"
        }),
        FunctionParam.new!(%{
          name: "notes",
          type: :string,
          description: "Notes about the activity. How it went, heart rate, etc"
        })
      ],
      function: &execute_create_fitness_log/2
    })
  end

  @spec execute_create_fitness_log(args :: %{String.t() => any()}, context :: map()) :: String.t()
  def execute_create_fitness_log(
        %{} = args,
        %{live_view_pid: _pid, current_user: user} = _context
      ) do
    # Use the context for the current_user
    case FitnessLogs.create_fitness_log(user.id, args) do
      {:ok, log} ->
        # send(pid, {:function_run, "Recorded fitness activity entry."})
        {:ok, "created log ##{log.id}"}

      {:error, changeset} ->
        errors = LangChain.Utils.changeset_error_to_string(changeset)
        {:error, "ERROR: #{errors}"}
    end
  end

  ## TODO: Spec, tests
  # def execute_create_fitness_log(input, _context) do
  #     %{prompt: prompt, model: model, tools: tools} = setup_llm_chain_with_tools()
  #     chain = LangChain.Chains.LLMChain.new(llm: model, prompt: prompt, tools: tools)

  #   try do
  #     result = LangChain.Chains.LLMChain.run(chain, input)
  #       Logger.info(result, label: "LangChain.Chains.run result:")
  #       result
  #     catch
  #         error ->
  #           Logger.error(error, label: "try/catch error:")
  #           {:error, error}
  #   end
  # end

def setup_llm_chain_with_tools() do
    prompt = """
      Create a json object for workout information and return the following schema:
       {
         "date": "{{date}}",
         "activity": "{{activity}}",
         "amount": {{amount}},
          "units": "{{units}}",
          "notes": "{{notes}}"
        }
     """

    model =
      case Application.get_env(:langchain_demo, :chat_model, :openai) do
        :openai ->
          %LangChain.ChatModels.ChatOpenAI{
            model: Application.get_env(:langchain_demo, :openai_model) || "gpt-4",
            temperature: 0.0,
           stream: true,
              tool_choice: :auto,
             api_key: Application.get_env(:langchain, :openai_key).()
           }
       :google ->
         %LangChain.ChatModels.ChatGoogleAI{
            model: "gemini-2.0-flash-exp",
             temperature: 0.0,
              stream: true,
              #tool_choice: :auto,
             api_key: Application.get_env(:langchain, :google_ai_key).() || Application.get_env(:langchain, :api_key).()
          }
        end

      tools = [
       %LangChain.Function{
          name: "update_current_user",
            description:
              "Update one or more fields at a time on the user's account and workout information.",
          display_text: "Update user",
            strict: false,
          function: &LangChainDemoWeb.AgentChatLive.Agent.UpdateCurrentUserFunction.execute/2,
          async: true,
        parameters: [
            %LangChain.FunctionParam{
             name: "age",
                type: :integer,
               description: "The user's age",
               required: false
             },
            %LangChain.FunctionParam{
                name: "overall_fitness_plan",
               type: :string,
               description: "Description of the user's current overall fitness plan",
               required: false
               },
               %LangChain.FunctionParam{
               name: "fitness_experience",
                 type: :string,
                  description: "The user's experience with physical fitness. Used to customize instructions.",
                enum: ~w(beginner intermediate advance),
               required: false
               },
                 %LangChain.FunctionParam{
                 name: "gender",
                  type: :string,
                 description: "The user's gender. Used to help customize workouts",
                  required: false
               },
            %LangChain.FunctionParam{
               name: "goals",
                type: :string,
                  description:
                "The user's current set of goals. CSV list of goals. (Ex: 12 bicep curls at 35 lbs, run a mile without walking)",
                  required: false
              },
                %LangChain.FunctionParam{
                   name: "name",
                  type: :string,
                    description: "The user's name. Used to customize the interaction and training",
                  required: false
                },
                %LangChain.FunctionParam{
                name: "resources",
                 type: :string,
               description: "CSV list of fitness resources available to the user. (Ex: gym membership, rack of free weight dumbbells, stationary bike)",
                 required: false
               },
               %LangChain.FunctionParam{
                name: "why",
                   type: :string,
                description:
                "The user's reasons for wanting to improve fitness. Used for motivation and to customize the fitness plan to satisfy the user",
                 required: false
               },
                %LangChain.FunctionParam{
                 name: "limitations",
                 type: :string,
                   description:
                   "CSV list of any physical limitations the user has that may impact which exercises they can do",
                    required: false
                },
                  %LangChain.FunctionParam{
                   name: "notes",
                    type: :string,
                   description:
                    "Place to store relevant and temporary notes about the user for future reference",
                    required: false
                  },
                %LangChain.FunctionParam{
                   name: "fitness_plan_for_week",
                     type: :string,
                   description: "The user's specific workout plan for the week",
                    required: false
                }
            ]
        },
          %LangChain.Function{
            name: "get_fitness_logs",
            description: "Search for and return the user's past fitness workout logs as a JSON array.",
            display_text: "Request fitness logs",
          strict: false,
           function: &LangChainDemoWeb.AgentChatLive.Agent.FitnessLogsTool.execute_get_fitness_logs/2,
            parameters: [
               %LangChain.FunctionParam{
                name: "days",
                   type: :integer,
                   description: "The number of days of history to return from the search. Defaults to 12",
                   required: false
               },
              %LangChain.FunctionParam{
                name: "activity",
                 type: :string,
               description: "The name of the activity being search for. Searches for one activity at a time, but supports partial matches. An activity of \"bench\" returns both Incline Bench and Bench Press",
                  required: false
               }
           ]
        },
        %LangChain.Function{
          name: "create_fitness_log",
            description: "Create a new fitness log entry for the user.",
         display_text: "Record fitness log entry",
          strict: false,
          function: &LangChainDemoWeb.AgentChatLive.Agent.FitnessLogsTool.execute_create_fitness_log/2,
           parameters: [
             %LangChain.FunctionParam{
                 name: "date",
               type: :string,
                 description: "The date the activity was performed as a string in the format YYYY-MM-DD",
                    required: false
               },
              %LangChain.FunctionParam{
                  name: "activity",
                    type: :string,
                  description: "The name of the activity. Ex: Running, Elliptical, Bench Press, Push Ups, Bent-Over Rows, etc",
                  required: false
                },
              %LangChain.FunctionParam{
                 name: "amount",
                   type: :integer,
                 description: "Either the duration in time, a distance traveled, the number of times an activity was performed (like push-ups), or the weight used (like \"25\" for 25 lbs)",
                  required: false
               },
              %LangChain.FunctionParam{
                  name: "units",
                    type: :string,
                description: "One word unit for the amount. Ex: lbs, minutes, miles, count",
                    required: false
                  },
                %LangChain.FunctionParam{
                name: "notes",
                   type: :string,
                    description: "Notes about the activity. How it went, heart rate, etc",
                     required: false
              }
          ]
        }
    ]
      %{prompt: prompt, model: model, tools: tools}
  end
end
