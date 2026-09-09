#' Server logic for a generative UI canvas
#'
#' Wires a [genui_catalog()] to an ellmer `Chat`: compiles every component
#' into a schema-validated tool, registers the built-in lifecycle tools
#' (`update_component`, `remove_component`, `clear_canvas`), installs the
#' assembled system prompt, and executes validated tool calls against the
#' [genui_canvas()] with the matching `id`. Components stream onto the
#' canvas progressively as the model emits tool calls; validation and
#' rendering failures are returned to the model as tool errors and never
#' crash the session.
#'
#' With `chat_id`, the package connects a [shinychat::chat_ui()] you placed
#' in the UI using [shinychat::chat_server()]. It handles asynchronous
#' streaming, cancellation, and attachments. Set `allow_attachments = FALSE`
#' in `chat_ui()` to disable uploads; attachments provide context to the
#' model and do not replace the component `data`. Conversation history is
#' disabled because restoring a conversation also requires restoring its
#' canvas and registry. With `chat_id = NULL` you run your own loop on
#' `chat`; the registered tools work all the same.
#'
#' Create the `Chat` object inside your server function, one per session.
#' Sharing a single `Chat` across sessions would cross-wire the tool
#' closures and leak conversation history between users.
#'
#' @section Update semantics:
#' `update_component` re-instantiates the component's module with the merged
#' arguments inside the instance's stable shell: same canvas position, same
#' ids, no page flicker. Because the module restarts, embedded input state
#' (like the starter histogram's bin slider) resets to its defaults on
#' update; snapshotting and restoring embedded input values across updates
#' is explicitly future work.
#'
#' @section Error feedback:
#' Any failure while handling a tool call --- schema validation, a
#' component's `check()` hook, or a rendering error --- is signaled as a
#' regular R condition. ellmer catches it and returns
#' `conditionMessage()` to the model as the tool error, so the model can
#' correct its arguments and retry; the Shiny session itself never crashes,
#' and a failed call never leaves a half-rendered component behind.
#' Failures are always logged to the app's server log; set
#' `options(shinygenui.verbose = TRUE)` to also log successful canvas
#' operations.
#'
#' @param id Module id, matching the [genui_canvas()] `id`.
#' @param catalog A [genui_catalog()].
#' @param chat An ellmer `Chat` object (any provider). Its system prompt is
#'   replaced with `system_prompt`.
#' @param data A reactive (or function) returning the app's current data
#'   object. It is passed to component `server()` functions and, isolated,
#'   to `check()` hooks at validation time.
#' @param chat_id Id of a [shinychat::chat_ui()] placed in the UI at the
#'   same namespace level as [genui_canvas()], or `NULL` (default) to manage
#'   the chat loop yourself.
#' @param greeting Optional markdown welcome message, shown while the chat
#'   is empty and dismissed after the first user message (only used when
#'   `chat_id` is set). It is display-only and never sent to the model.
#' @param system_prompt System prompt to install on `chat`. Defaults to
#'   [genui_prompt()] of the catalog; use `genui_prompt(catalog, context =
#'   ...)` to add app context, or pass any string to take full control.
#'
#' @return (Invisibly) a list with `chat` (the wired `Chat`), and the
#'   reactives `trace` (the ordered call trace, see [genui_trace()]) and
#'   `instances` (the live instance state, a named list keyed by id).
#' @export
#' @examples
#' note <- genui_component(
#'   name = "note_card",
#'   description = "A card showing a short note.",
#'   args = list(text = "The note text."),
#'   ui = function(id, args) htmltools::p(args$text)
#' )
#' catalog <- genui_catalog(note)
#' chat <- ellmer::chat_openai(
#'   model = "gpt-5.6-sol",
#'   credentials = function() list(api_key = "not-used")
#' )
#' shiny::testServer(
#'   genui_server,
#'   args = list(id = "canvas", catalog = catalog, chat = chat),
#'   {
#'     stopifnot("note_card" %in% names(chat$get_tools()))
#'   }
#' )
genui_server <- function(
  id,
  catalog,
  chat,
  data = NULL,
  chat_id = NULL,
  greeting = NULL,
  system_prompt = NULL
) {
  check_catalog(catalog)
  if (!inherits(chat, "Chat")) {
    genui_abort("{.arg chat} must be an ellmer {.cls Chat} object, like {.code ellmer::chat_openai()}.")
  }
  if (!is.null(chat_id) && !is_string(chat_id)) {
    genui_abort("{.arg chat_id} must be a single string or `NULL`.")
  }

  # The developer places chat_ui() alongside genui_canvas(), so the chat's
  # inputs live in the *caller's* namespace, not inside this module.
  parent_session <- shiny::getDefaultReactiveDomain()
  if (is.null(parent_session)) {
    genui_abort("{.fn genui_server} must be called from within a Shiny server function.")
  }

  shiny::moduleServer(id, function(input, output, session) {
    engine <- GenuiEngine$new(catalog, session = session, data = data)

    trace_rv <- shiny::reactiveVal(list())
    instances_rv <- shiny::reactiveVal(list())
    engine$registry$set_on_change(function() {
      trace_rv(engine$registry$trace())
      instances_rv(engine$registry$snapshot()$instances)
    })

    # Findable by genui_trace() from anywhere in this Shiny session.
    store <- session$userData$shinygenui
    if (is.null(store)) {
      store <- new.env(parent = emptyenv())
      session$userData$shinygenui <- store
    }
    handles <- list(
      engine = engine,
      trace = shiny::reactive(trace_rv()),
      instances = shiny::reactive(instances_rv())
    )
    assign(session$ns(NULL), handles, envir = store)

    chat$set_system_prompt(system_prompt %||% genui_prompt(catalog))
    for (tool in compile_tools(catalog, engine)) {
      chat$register_tool(tool)
    }

    if (!is.null(chat_id)) {
      wire_chat(
        chat = chat,
        chat_id = chat_id,
        greeting = greeting,
        session = parent_session
      )
    }

    invisible(list(
      chat = chat,
      trace = handles$trace,
      instances = handles$instances
    ))
  })
}

# chat_server() also uses the current domain for observers and asynchronous
# appends, so bind both it and the explicit session to the caller's scope.
wire_chat <- function(chat, chat_id, greeting, session) {
  if (is.null(greeting) || !any(nzchar(greeting))) {
    greeting <- NULL
  } else {
    greeting <- paste(greeting, collapse = "\n")
  }

  shiny::withReactiveDomain(session, {
    shinychat::chat_server(
      chat_id,
      client = chat,
      greeting = greeting,
      history = FALSE,
      session = session
    )
  })
}
