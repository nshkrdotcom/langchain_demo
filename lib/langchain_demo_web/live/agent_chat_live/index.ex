defmodule LangChainDemoWeb.AgentChatLive.Index do
  use LangChainDemoWeb, :live_view
  require Logger

  alias Phoenix.LiveView.AsyncResult
  alias LangChainDemoWeb.AgentChatLive.Agent.ChatMessage
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.ChatModels.ChatGoogleAI
  alias LangChain.PromptTemplate
  alias LangChainDemoWeb.AgentChatLive.Agent.UpdateCurrentUserFunction
  alias LangChainDemoWeb.AgentChatLive.Agent.FitnessLogsTool
  alias LangChainDemo.FitnessUsers
  alias LangChainDemo.FitnessLogs

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      # fake current_user setup.
      # Data expected after `mix ecto.setup` from the `seeds.exs`
      |> assign(:current_user, FitnessUsers.get_fitness_user!(1))
      |> assign(:is_loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    Logger.info("***** [def handle_params(_params, _uri, socket) do] Handle PARAMS!")
    socket =
      socket
      # display a prompt message for the UI that isn't used in the actual conversations
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
    is_new = ChatMessage.new(params)
    socket =
      case is_new do
        {:ok, %ChatMessage{} = message} ->
          socket
        |> add_user_message(message.content)

        #|> assign(:form, to_form(%Ecto.Changeset{data: %ChatMessage{}, changes: %{content: "Please Wait..."}}))
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

  @impl true
  def handle_info({:chat_delta, %LangChain.MessageDelta{} = delta}, socket) do
    try do
      updated_chain = LLMChain.apply_delta(socket.assigns.llm_chain, delta)
      ### THREE WAYS to access the llm_chain fields:
      # Logger.info("Status: #{case socket.assigns.llm_chain.delta do
      #   %LangChain.MessageDelta{status: status} -> status
      #   nil -> "nil"
      #   _ -> "unexpected structure"
      # end}")
      # Logger.info("Status: #{(socket.assigns.llm_chain.delta && socket.assigns.llm_chain.delta.status) || "no status"}")
      #Logger.info("Delta: #{inspect(socket.assigns.llm_chain.delta)}")
      #Logger.info("updated_chain: #{inspect(updated_chain.delta, limit: 12, pretty: true)}")
      {:noreply, assign(socket, :llm_chain, updated_chain)}
    catch
      error, stacktrace ->
        Logger.error("Error processing chat delta: #{inspect(error)}\nStacktrace: #{inspect(stacktrace)}")
        {:noreply, put_flash(socket, :error, "Failed to process chat message")}
    end
  end

  @impl true
  def handle_info({:chat_complete, updated_chain}, socket) do
    try do
      socket =
        socket
        |> append_display_message(%ChatMessage{
            role: updated_chain.last_message.role,
            hidden: true,
            content: updated_chain.last_message.content,
          })
        #|> reset_chat_message_form()
      #Logger.info("updated_chain: #{inspect(updated_chain.last_message, limit: :infinity, pretty: true)}\n socket: #{inspect(socket, limit: :infinity, pretty: true)}")
      {:noreply, assign(socket, :llm_chain, updated_chain)}
    catch
      error, stacktrace ->
        Logger.error("Error processing chat delta: #{inspect(error)}\nStacktrace: #{inspect(stacktrace)}")
        {:noreply, put_flash(socket, :error, "Failed to process chat message")}
    end
  end

  def handle_info({:tool_executed, tool_message}, socket) do
    try do
      message = %ChatMessage{
        role: tool_message.role,
        content: tool_message.content,
        tool_calls: tool_message.tool_calls,
        tool_results: tool_message.tool_results
      }
      socket =
        socket
        |> assign(:llm_chain, LLMChain.add_message(socket.assigns.llm_chain, tool_message))
        |> append_display_message(message)
        |> clear_loading()
      {:noreply, socket}
    catch
      error, stacktrace ->
        Logger.error("Error processing tool message: #{inspect(error)}\nStacktrace: #{inspect(stacktrace)}")
        {:noreply, put_flash(socket, :error, "Failed to process tool response")}
    end
  end

  def handle_info({:updated_current_user, updated_user}, socket) do
    try do
      socket =
        socket
        |> assign(:current_user, updated_user)
        |> assign(
          :llm_chain,
          LLMChain.update_custom_context(socket.assigns.llm_chain, %{current_user: updated_user})
        )
      {:noreply, socket}
    catch
      error, stacktrace ->
        Logger.error("Error updating user context: #{inspect(error)}\nStacktrace: #{inspect(stacktrace)}")
        {:noreply, put_flash(socket, :error, "Failed to update user information")}
    end
  end

  def handle_info({:task_error, reason}, socket) do
    Logger.error("Task error: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Error with chat: #{format_error_message(reason)}")}
  end

  def handle_info(msg, socket) do
    Logger.debug("Unhandled message received: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl true
  @doc """
  Handles async function returning a successful result
  """
  def handle_async(:running_llm, {:ok, :ok = _success_result}, socket) do
    socket =
      socket
      |> assign(:async_result, AsyncResult.ok(%AsyncResult{}, :ok))
      |> clear_loading()

    {:noreply, socket}
  end

  def handle_async(:running_llm, {:ok, {:error, reason}}, socket) do
    error_message = format_error_message(reason)
    socket =
      socket
      |> put_flash(:error, error_message)
      |> assign(:async_result, AsyncResult.failed(%AsyncResult{}, reason))
      |> clear_loading()

    {:noreply, socket}
  end

  def handle_async(:running_llm, {:exit, reason}, socket) do
    error_message = "Chat service error: #{format_error_message(reason)}"
    socket =
      socket
      |> put_flash(:error, error_message)
      |> assign(:async_result, AsyncResult.failed(%AsyncResult{}, reason))
      |> clear_loading()

    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
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

    current_user_template =
      PromptTemplate.from_template!(~S|
Today is <%= @today %>

Current account information in JSON format:
<%= @current_user_json %>

Do an accountability follow-up with me on my previous workouts. When no previous workout information is available, help me get started.

Today's workout information in JSON format:
<%= @current_workout_json %>

This text ALREADYSENT was already sent by you to the user, so do not introduce yourself. They should answer your question in the below prompt.
```ALREADYSENT
  Hello! My name is Max and I'm your personal trainer! How can I help you today?
```

User says:
<%= @user_text %>|)
    with {:ok, current_user_json} <- Jason.encode(current_user),
        {:ok, current_workout_json} <- FitnessLogs.list_fitness_logs(current_user.id, days: 0)
      |> Jason.encode() do
      updated_message = PromptTemplate.to_message!(current_user_template, %{
        current_user_json: current_user_json,
        current_workout_json: current_workout_json,
        today: today |> Calendar.strftime("%A, %Y-%m-%d"),
        user_text: user_text
      })
      updated_chain =
        llm_chain
        |> LLMChain.add_message(updated_message)

      socket
      |> assign(llm_chain: updated_chain)
      |> append_display_message(%ChatMessage{role: :user, content: user_text})
      |> set_loading()
    else
      error ->
        IO.inspect("Error encoding data for prompt template", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
        IO.inspect(error, label: "Error", limit: Application.get_env(:langchain_demo, :io_inspect_limit, :infinity))
        # Handle the error, maybe by using default values or sending an error message
        socket
    end
  end

  def add_user_message(socket, user_text) when is_binary(user_text) do
    # NOT the first message. Submit the user's text as-is.
    updated_chain = LLMChain.add_message(socket.assigns.llm_chain, Message.new_user!(user_text))

    socket
    |> assign(llm_chain: updated_chain)
    |> append_display_message(%ChatMessage{role: :user, content: user_text})
    |> set_loading()
  end

  defp assign_llm_chain(socket) do
    system_prompt_text = ~S|
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

Before modifying the user's training program, summarize the change and confirm the change.|
    live_view_pid = self()
    llm_chain =
      LLMChain.new!(%{
        llm:
          ChatGoogleAI.new!(%{
            model: "gemini-1.5-flash-8b",
            temperature: 0,
            stream: true,
            api_key: Application.get_env(:langchain, :google_ai_key).()
          }),
        custom_context: %{
          live_view_pid: live_view_pid,
          current_user: socket.assigns.current_user
        },
        verbose: false
      })
      |> LLMChain.add_tools(UpdateCurrentUserFunction.new!())
      |> LLMChain.add_tools(FitnessLogsTool.new_functions!())
      |> LLMChain.add_message(Message.new_system!(system_prompt_text))
      |> LLMChain.add_llm_callback(%{
        on_llm_new_delta: fn _model, delta ->
          send(live_view_pid, {:chat_delta, delta})
        end,
        on_llm_new_message: fn _model, message ->
          send(live_view_pid, {:tool_executed, message})
        end,
        on_llm_token_usage: fn _model, usage ->
          Logger.info("TOKEN USAGE: #{inspect(usage)}")
        end,
        on_llm_ratelimit_info: fn _model, rate_limit ->
          Logger.info("Rate Limit Info: #{inspect(rate_limit)}")
        end
      })

    socket
    |> assign(:llm_chain, llm_chain)

  end

  def run_chain(socket) do
    chain = socket.assigns.llm_chain
    live_view_pid = self()

    socket
    |> assign(:llm_chain, chain)
    |> assign(:async_result, AsyncResult.loading())
    |> start_async(:running_llm, fn ->
      result = LLMChain.run(chain, while_needs_response: true)
      case result do
        {:ok, updated_chain} ->
          send(live_view_pid, {:chat_complete, updated_chain})
          :ok
        {:error, reason} ->
          {:error, format_error_message(reason)}
        unexpected ->
          Logger.error("Unexpected chain response: #{inspect(unexpected)}")
          {:error, "Unexpected response from chat service"}
      end
    end)
  end

  defp format_error_message(reason) when is_binary(reason), do: reason
  defp format_error_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error_message(reason), do: inspect(reason)

  defp reset_chat_message_form(socket) do
    changeset = ChatMessage.create_changeset(%{})
    assign_form(socket, changeset)
  end

  defp append_display_message(socket, %ChatMessage{} = message) do
    assign(socket, :display_messages, socket.assigns.display_messages ++ [message])
  end

  defp set_loading(socket) do
    assign(socket, :is_loading, true)
  end

  defp clear_loading(socket) do
    assign(socket, :is_loading, false)
  end
end
