defmodule LangChainDemoWeb.AgentChatLive.Index do
  use LangChainDemoWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias LangChainDemoWeb.AgentChatLive.Agent.ChatMessage
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.PromptTemplate
  alias LangChainDemoWeb.AgentChatLive.Agent.UpdateCurrentUserFunction
  alias LangChainDemoWeb.AgentChatLive.Agent.FitnessLogsTool
  alias LangChainDemo.FitnessUsers
  alias LangChainDemo.FitnessUsers.FitnessUser

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      # fake current_user setup.
      # Data expected after `mix ecto.setup` from the `seeds.exs`
      |> assign(:current_user, FitnessUsers.get_fitness_user!(1))

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
          |> submit_message(Message.new_user!(message.content))
          |> reset_chat_message_form()

        {:error, changeset} ->
          assign_form(socket, changeset)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_response, %LangChain.MessageDelta{} = delta}, socket) do
    updated_chain = LLMChain.apply_delta(socket.assigns.llm_chain, delta)
    # if this completed the delta and it's not a message, create the message
    socket =
      if updated_chain.delta == nil do
        {:ok, message} = Message.new(Map.from_struct(updated_chain.last_message))
        append_message(socket, message)
      else
        socket
      end

    {:noreply, assign(socket, :llm_chain, updated_chain)}
  end

  def handle_info({:updated_current_user, updated_user}, socket) do
    message = %ChatMessage{
      role: :function_call,
      hidden: false,
      content: "Updated your information."
    }

    socket =
      socket
      |> assign(:current_user, updated_user)
      |> assign(
        :llm_chain,
        LLMChain.update_custom_context(socket.assigns.llm_chain, %{current_user: updated_user})
      )
      |> assign(:display_messages, socket.assigns.display_messages ++ [message])

    {:noreply, socket}
  end

  def handle_info({:function_run, message}, socket) do
    message = %ChatMessage{
      role: :function_call,
      hidden: false,
      content: message
    }

    socket =
      socket
      |> assign(:display_messages, socket.assigns.display_messages ++ [message])

    {:noreply, socket}
  end

  def handle_info({:task_error, reason}, socket) do
    socket = put_flash(socket, :error, "Error with chat. Reason: #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  # handles async function returning a successful result
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

    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  def submit_message(socket, %Message{} = message) do
    socket
    |> append_message(message)
    |> run_chain()
  end

  defp assign_llm_chain(socket) do
    date = DateTime.utc_now()

    current_user_template =
      PromptTemplate.from_template!(
        ~S|
Today is <%= @date %>

The user's currently known information in JSON format:
<%= @current_user_json %>

Do an accountability follow-up with me on my previous workouts. When there is no previous workout information, help me get started.|
      )

    llm_chain =
      LLMChain.new!(%{
        llm:
          ChatOpenAI.new!(%{
            model: "gpt-4",
            # don't get creative with answers
            temperature: 0,
            request_timeout: 60_000,
            stream: true
          }),
        custom_context: %{
          live_view_pid: self(),
          current_user: socket.assigns.current_user
        },
        verbose: false
      })
      |> LLMChain.add_functions(UpdateCurrentUserFunction.new!())
      |> LLMChain.add_functions(FitnessLogsTool.new_functions!())
      |> LLMChain.add_message(
        Message.new_system!(
          ~S|
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

Before modifying the user's training program, summarize the change and confirm it is what they want.|
        )
      )
      |> LLMChain.add_message(
        PromptTemplate.to_message!(current_user_template, %{
          current_user_json: FitnessUser.for_json(socket.assigns.current_user) |> Jason.encode!(),
          date: date |> Calendar.strftime("%A, %Y/%m/%d")
        })
      )

    socket
    |> assign(:llm_chain, llm_chain)
  end

  def run_chain(socket) do
    chain = socket.assigns.llm_chain
    live_view_pid = self()

    callback_fn = fn
      %LangChain.MessageDelta{} = delta ->
        send(live_view_pid, {:chat_response, delta})

      %LangChain.Message{} = _message ->
        # disregard the full-message callback. We'll use the delta
        # send(live_view_pid, {:chat_response, message})
        :ok
    end

    socket
    |> assign(:async_result, AsyncResult.loading())
    |> start_async(:running_llm, fn ->
      case LLMChain.run(chain, while_needs_response: true, callback_fn: callback_fn) do
        # Don't return a large success result. Callbacks return what we want.
        {:ok, _updated_chain, _last_message} ->
          :ok

        # return the errors for display
        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp reset_chat_message_form(socket) do
    changeset = ChatMessage.create_changeset(%{})
    assign_form(socket, changeset)
  end

  defp append_message(socket, %Message{} = llm_message) do
    llm_chain =
      socket.assigns.llm_chain
      |> LLMChain.add_message(llm_message)

    socket = assign(socket, :llm_chain, llm_chain)

    case llm_message do
      # Messages that only execute a function have no content. Don't display if no content.
      %Message{role: role, content: content} = msg
      when role in [:user, :assistant] and is_binary(content) ->
        assign(socket, :display_messages, socket.assigns.display_messages ++ [msg])

      # not a message for display
      _other ->
        socket
    end
  end

  attr(:role, :atom, required: true)

  defp icon_for_role(assigns) do
    icon_name =
      case assigns.role do
        :assistant ->
          "hero-computer-desktop"

        :function_call ->
          "hero-cog-8-tooth"

        _other ->
          "hero-user"
      end

    assigns = assign(assigns, :icon_name, icon_name)

    ~H"""
    <.icon name={@icon_name} />
    """
  end
end
