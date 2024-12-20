defmodule LangChainDemoWeb.AgentChatLive.Index do
  use LangChainDemoWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias LangChainDemoWeb.AgentChatLive.Agent.ChatMessage
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  #alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatGoogleAI
  alias LangChain.PromptTemplate
  alias LangChainDemoWeb.AgentChatLive.Agent.UpdateCurrentUserFunction
  alias LangChainDemoWeb.AgentChatLive.Agent.FitnessLogsTool
  alias LangChainDemo.FitnessUsers
  alias LangChainDemo.FitnessLogs

  @impl true
  def mount(%{"show_detailed_errors" => show_detailed_errors} = _params, _session, socket)
    when show_detailed_errors in ["true", "false"] do
    socket =
      socket
      # fake current_user setup.
      # Data expected after `mix ecto.setup` from the `seeds.exs`
      |> assign(:current_user, FitnessUsers.get_fitness_user!(1))
      |> assign(:show_detailed_errors, show_detailed_errors == "true")

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      # fake current_user setup.
      # Data expected after `mix ecto.setup` from the `seeds.exs`
      |> assign(:current_user, FitnessUsers.get_fitness_user!(1))
      |> assign(:show_detailed_errors, false)
    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      socket
      # display a prompt message for the UI that isn't used in the actual
      # conversations
      |> assign(:display_messages, [
        %ChatMessage{
          role: :assistant,
          hidden: false,
          content:
            "Hello! My name is Max and I'm your personal trainer! How can I help you today?"
        }
      ])
      |> reset_chat_message_form()
      |> assign_llm_chain()
      |> assign(:async_result, %AsyncResult{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"chat_message" => params}, socket) do
    changeset =
      params
      |> ChatMessage.create_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"chat_message" => params}, socket) do
    socket =
      case ChatMessage.new(params) do
        {:ok, %ChatMessage{} = message} ->
          socket
          |> add_user_message(message.content)
          |> reset_chat_message_form()
          |> run_chain()

        {:error, changeset} ->
          assign_form(socket, changeset)
      end

    {:noreply, socket}
  end

  # Browser hook sent up the user's timezone.
  #@impl true
  def handle_event("browser-timezone", %{"timezone" => timezone}, socket) do
    # check user's settings. If timezone is different from settings, update it
    # on the user.
    user = socket.assigns.current_user

    socket =
      if timezone != user.timezone do
        {:ok, updated_user} = FitnessUsers.update_fitness_user(user, %{timezone: timezone})

        socket
        |> assign(:current_user, updated_user)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("toggle-detailed-errors", _params, socket) do
    {:noreply, update(socket, :show_detailed_errors, &(!&1))}
  end

  @impl true
  def handle_info({:chat_delta, %LangChain.MessageDelta{} = delta}, socket) do
    # This is where LLM generated content gets processed and merged to the
    # LLMChain managed by the state in this LiveView process.
    # Apply the delta message to our tracked LLMChain. If it completes the
    # message, display the message
    updated_chain = LLMChain.apply_delta(socket.assigns.llm_chain, delta)
    # if this completed the delta, create the message and track on the chain
    socket =
      if updated_chain.delta == nil do
        # the delta completed the message. Examine the last message
        message = updated_chain.last_message

        append_display_message(socket, %ChatMessage{
          role: message.role,
          content: message.content,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results
        })
      else
        socket
      end

    {:noreply, assign(socket, :llm_chain, updated_chain)}
  end

  def handle_info({:tool_executed, tool_message}, socket) do
    message = %ChatMessage{
      role: tool_message.role,
      hidden: false,
      content: nil,
      tool_results: tool_message.tool_results
    }

    socket =
      socket
      |> assign(:llm_chain, LLMChain.add_message(socket.assigns.llm_chain, tool_message))
      |> append_display_message(message)

    {:noreply, socket}
  end

  def handle_info({:updated_current_user, updated_user}, socket) do
    socket =
      socket
      |> assign(:current_user, updated_user)
      |> assign(
        :llm_chain,
        LLMChain.update_custom_context(socket.assigns.llm_chain, %{current_user: updated_user})
      )

    {:noreply, socket}
  end

  def handle_info({:task_error, reason}, socket) do
    socket = put_flash(socket, :error, "Error with chat. Reason: #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  @impl true
  @doc """
  Handles async function returning a successful result
  """
  def handle_async(:running_llm, {:ok, :ok = _success_result}, socket) do
    # discard the result of the successful async function. The side-effects are
    # what we want.
    socket =
      socket
      |> assign(:async_result, AsyncResult.ok(%AsyncResult{}, :ok))

    {:noreply, socket}
  end

  # handles async function returning an error as a result
  def handle_async(:running_llm, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> put_flash(:error, reason)
      |> assign(:async_result, AsyncResult.failed(%AsyncResult{}, reason))

    {:noreply, socket}
  end

  # handles async function exploding
  def handle_async(:running_llm, {:exit, reason}, socket) do
    socket =
      socket
      |> put_flash(:error, "Call failed: #{inspect(reason)}")
      |> assign(:async_result, %AsyncResult{})

    # when in verbose mode, log more details
    if socket.assigns.show_detailed_errors do
      IO.inspect("Error caught in LLMChain.run within start_async", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
      IO.inspect(reason, label: "Reason", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
    end

    {:noreply, socket}
  end

  def handle_async(:get_fitness_data, {:ok, current_workout_data}, socket) do
    current_workout_data =
    try do
      Jason.encode(current_workout_data)
    catch
      _e, _stacktrace ->
      "[]"
    end
    updated_chain =
      socket.assigns.llm_chain
      |> LLMChain.add_message(
        PromptTemplate.to_message!(
          PromptTemplate.from_template!(~S|
      Today is <%= @today %>

      Current account information in JSON format:
      <%= @current_user_json %>

      Do an accountability follow-up with me on my previous workouts. When no previous workout information is available, help me get started.

      Today's workout information in JSON format:
      <%= @current_workout_json %>

      User says:
      <%= @user_text %>|), %{
          current_user_json: socket.assigns.current_user_json,
          current_workout_json: current_workout_data,
          today: socket.assigns.today |> Calendar.strftime("%A, %Y-%m-%d"),
          user_text: socket.assigns.user_text
        })
      )

    socket
    |> assign(llm_chain: updated_chain)
    # display what the user said, but not what we sent.
    |> append_display_message(%ChatMessage{role: :user, content: socket.assigns.user_text})
    |> assign(:async_result, %AsyncResult{})
    |> run_chain()
   {:noreply, socket}
end

  # the first user message
  def add_user_message(socket, user_text) when is_binary(user_text) do
    # NOT the first message. Submit the user's text as-is.
    updated_chain = LLMChain.add_message(socket.assigns.llm_chain, Message.new_user!(user_text))

    socket
    |> assign(llm_chain: updated_chain)
    |> append_display_message(%ChatMessage{role: :user, content: user_text})
  end

  defp assign_llm_chain(socket) do
    llm_chain =
      LLMChain.new!(%{
        llm:

          # ChatOpenAI.new!(%{
          #   model: "gpt-4",
          #   # don't get creative with answers
          #   temperature: 0,
          #   request_timeout: 60_000,
          #   stream: true,
          #   api_key: Application.get_env(:langchain, :openai_key).()
          # }),

          ChatGoogleAI.new!(%{
            model: "gemini-1.5-flash-8b",
            # don't get creative with answers
            temperature: 0,
            request_timeout: 60_000,
            stream: true,
            api_key: Application.get_env(:langchain, :google_ai_key).()
          }),
        custom_context: %{
          live_view_pid: self(),
          current_user: socket.assigns.current_user
        },
        verbose: false
      })
      |> LLMChain.add_tools(UpdateCurrentUserFunction.new!())
      |> LLMChain.add_tools(FitnessLogsTool.new_functions!())
      |> LLMChain.add_message(Message.new_system!(~S|
You are a helpful American virtual personal strength trainer. Your name is "Max". Limit discussions
to ONLY discuss the user's fitness programs and fitness goals. You speak in a natural, casual and conversational tone.
Help the user to improve their fitness and strength. Do not answer questions
off the topic of fitness and exercising. Answer the user's questions when possible.
If you don't know the answer to something, say you don't know; do not make up answers.

Your goal is to help user work towards their goal. Do this by:
- Identifying the user's "why" or their motivation for their fitness goal. Refer to one or more of the user's "why" reasons to encourage and motivate them.
- Determine their current level of fitness through the user_account function or fallback to asking questions when existing data isn't available.
- Focus on strength training.
- Ask about any injuries or limitations to tailor the program to the user's abilities.
- Recommend only safe and accepted strategies and exercises.
- Create a fitness plan for the user that will help them get to the next level of fitness.
- Record the user's available resources on their user_account and use those resources when applicable. Resources can be gym memberships, home workout equipment, workout videos, etc.
- Always be encouraging.
- Be the user's accountability partner. Follow-up with the user on their exercises and how well they are following the program.
- YouTube videos can be a resource for cardio workouts or for example techniques for exercises.
- A weekly workout plan should be detailed and specific.

Format for weekly fitness plan:

**Day name** - Activity type and/or focus
- Activity: details like distance or sets and reps. (Weight if historical data is available)
- Activity: details. (Weight)

Before modifying the user's training program, summarize the change and confirm the change.|))

    socket
    |> assign(:llm_chain, llm_chain)
  end

  # if this is the FIRST user message, use a prompt template to include some
  # initial hidden instructions. We detect if it's the first by matching on the
  # last_messaging being the "system" message.
  def add_user_message(
        %{assigns: %{llm_chain: %LLMChain{last_message: %Message{role: :system}} = llm_chain}} =
          socket,
        user_text
      )
      when is_binary(user_text) do
    current_user = socket.assigns.current_user
    today = DateTime.now!(current_user.timezone)
    live_view_pid = self()

    current_user_template =
      PromptTemplate.from_template!(~S|
  Today is <%= @today %>

  Current account information in JSON format:
  <%= @current_user_json %>

  Do an accountability follow-up with me on my previous workouts. When no previous workout information is available, help me get started.

  Today's workout information in JSON format:
  <%= @current_workout_json %>

  User says:
  <%= @user_text %>|)

    socket =
    socket
    |> assign(:async_result, AsyncResult.loading())
    |> start_async(:get_fitness_data, fn ->
      try do
        FitnessLogs.list_fitness_logs(current_user.id, days: 0)
      catch
          e, stacktrace ->
            IO.inspect("Error in FitnessLogs.list_fitness_logs within start_async",
            limit: :infinity
          )
          IO.inspect(stacktrace, label: "Stacktrace", limit: :infinity)
          # Re-raise the error if you want it to terminate the process, or handle it gracefully
          {:error, %ArgumentError{message: message}}
       end
    end)

    with {:ok, current_user_json} <- Jason.encode(current_user) do
        socket
      |> assign(user_text: user_text)
      |> assign(llm_chain: llm_chain)
      |> assign(current_user_json: current_user_json)
      |> assign(today: today)
    else
      error ->
        IO.inspect("Error encoding data for prompt template", limit: :infinity)
        IO.inspect(error, label: "Error", limit: :infinity)
        # Handle the error, maybe by using default values or sending an error message
        socket
    end
  end

  def run_chain(socket) do
    chain = socket.assigns.llm_chain
    live_view_pid = self()

    socket =
      socket
      |> assign(
        :llm_chain,
        LLMChain.add_llm_callback(socket.assigns.llm_chain, %{
          on_llm_new_delta: fn _model, delta ->
            try do
              send(live_view_pid, {:chat_delta, delta})
            catch
              e, stacktrace ->
                IO.inspect("Error in on_llm_new_delta", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
                IO.inspect(e, label: "Error", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
                IO.inspect(stacktrace, label: "Stacktrace", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
            end
          end,
          on_llm_token_usage: fn _model, usage ->
            IO.inspect(usage)
            :ok
          end,
          on_llm_new_message: fn _model, message ->
            try do
              send(live_view_pid, {:tool_executed, message})
            catch
              e, stacktrace ->
                IO.inspect("Error in on_llm_new_message", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
                IO.inspect(e, label: "Error", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
                IO.inspect(stacktrace, label: "Stacktrace", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
            end
          end
        })
      )

    socket
    |> assign(:async_result, AsyncResult.loading())
    |> start_async(:running_llm, fn ->
      try do
        case LLMChain.run(chain, while_needs_response: true) do
          # Don't return a large success result. Callbacks return what we want.
          {:ok, _updated_chain, _last_message} ->
            :ok

          # return the errors for display
          {:error, reason} ->
            {:error, reason}
        end
      catch
        # Handle different error types if needed
        CaseClauseError, stacktrace ->
          IO.inspect("CaseClauseError caught in LLMChain.run within start_async",
            limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity)
          )
          IO.inspect(stacktrace, label: "Stacktrace", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
          # Re-raise the error if you want it to terminate the process, or handle it gracefully
          {:error, %CaseClauseError{}} # Convert to an error tuple

        # Catch-all for other errors
        e, stacktrace ->
          IO.inspect("Error caught in LLMChain.run within start_async", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
          IO.inspect(e, label: "Error", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
          IO.inspect(stacktrace, label: "Stacktrace", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
          # Re-raise or handle gracefully
          {:error, e} # Convert to an error tuple
      end
    end)
  end

  defp reset_chat_message_form(socket) do
    changeset = ChatMessage.create_changeset(%{})
    assign_form(socket, changeset)
  end

  defp append_display_message(socket, %ChatMessage{} = message) do
    assign(socket, :display_messages, socket.assigns.display_messages ++ [message])
  end


  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

end
