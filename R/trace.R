#' Read the ordered call trace of a canvas
#'
#' The trace is the spec of record for a canvas: every validated call the
#' model made (create, update, remove, clear), in order, as plain
#' JSON-friendly lists. [genui_replay()] can rebuild the canvas from it with
#' no LLM configured. Embedded input state is intentionally ephemeral and
#' never recorded.
#'
#' @param session The Shiny session (defaults to the current reactive
#'   domain).
#' @param id The [genui_server()] module id to read, relative to `session`.
#'   May be omitted when the session has exactly one canvas.
#'
#' @return A reactive expression returning the trace: a list of entries of
#'   the form `list(op = "create", id = "c1", component = "...", args =
#'   list(...))` (plus `parent_id` for children; `update` entries carry the
#'   validated argument delta). Persist it with [saveRDS()] to replay in a
#'   later session.
#' @export
genui_trace <- function(session = shiny::getDefaultReactiveDomain(), id = NULL) {
  find_genui_store(session, id)$trace
}

find_genui_store <- function(session, id, call = rlang::caller_env()) {
  if (is.null(session)) {
    genui_abort(
      "No Shiny session found; call this from within a server function.",
      call = call
    )
  }
  store <- session$userData$shinygenui
  keys <- if (is.null(store)) character() else ls(store)
  if (length(keys) == 0) {
    genui_abort(
      "No {.fn genui_server} (or {.fn genui_replay}) has run in this session yet.",
      call = call
    )
  }

  if (is.null(id)) {
    if (length(keys) > 1) {
      genui_abort(
        c(
          "Multiple canvases in this session; pass {.arg id}.",
          i = "Available ids: {.val {keys}}."
        ),
        call = call
      )
    }
    return(get(keys, envir = store))
  }

  for (key in unique(c(session$ns(id), id))) {
    if (key %in% keys) {
      return(get(key, envir = store))
    }
  }
  genui_abort(
    c(
      "No canvas with id {.val {id}} in this session.",
      i = "Available ids: {.val {keys}}."
    ),
    call = call
  )
}

#' Rebuild a canvas from a saved trace, no LLM required
#'
#' Folds a trace (from [genui_trace()], or the `trace` reactive returned by
#' [genui_server()]) through the same validate-and-execute pipeline the
#' model's tool calls use, recreating every instance in a [genui_canvas()]
#' with id `target`. Instance ids come back identical because ids are
#' assigned deterministically and never reused. Embedded inputs return at
#' their default values: input state is ephemeral by design and not part of
#' the trace.
#'
#' Entries that no longer validate (for example after the catalog changed)
#' are skipped with a warning; the rest of the trace still replays. The
#' target canvas is emptied first, so replaying twice is idempotent.
#'
#' @param trace A trace list, as returned by [genui_trace()] (already
#'   evaluated, not the reactive) or restored via [readRDS()].
#' @param catalog The [genui_catalog()] to render with; component names in
#'   the trace must exist in it.
#' @param target Module id of the [genui_canvas()] to rebuild into. Use a
#'   canvas of its own, not one already driven by [genui_server()].
#' @param data Optional reactive (or function) returning the data object,
#'   passed to component servers and `check()` hooks, as in
#'   [genui_server()].
#' @param session The Shiny session (defaults to the current reactive
#'   domain).
#'
#' @return (Invisibly) a list with reactives `trace` and `instances`
#'   describing the rebuilt canvas, as in [genui_server()].
#' @export
genui_replay <- function(
  trace,
  catalog,
  target,
  data = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  check_catalog(catalog)
  if (!is.list(trace)) {
    genui_abort("{.arg trace} must be a list of trace entries; did you pass the reactive instead of its value?")
  }
  if (is.null(session)) {
    genui_abort("{.fn genui_replay} must be called from within a Shiny server function.")
  }

  shiny::moduleServer(target, function(input, output, session) {
    engine <- GenuiEngine$new(catalog, session = session, data = data)

    # Make replay idempotent: empty the target canvas before rebuilding.
    shiny::removeUI(
      selector = paste0("#", session$ns("canvas"), " > .genui-shell"),
      multiple = TRUE,
      immediate = TRUE,
      session = session
    )

    for (i in seq_along(trace)) {
      tryCatch(
        engine$handle(trace_entry_call(trace[[i]])),
        error = function(e) {
          reason <- conditionMessage(e)
          cli::cli_warn(c("Skipping trace entry {i} during replay.", x = "{reason}"))
        }
      )
    }

    trace_rv <- shiny::reactiveVal(engine$registry$trace())
    instances_rv <- shiny::reactiveVal(engine$registry$snapshot()$instances)
    engine$registry$set_on_change(function() {
      trace_rv(engine$registry$trace())
      instances_rv(engine$registry$snapshot()$instances)
    })

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

    invisible(handles[c("trace", "instances")])
  })
}

# One trace entry back into the normalized call it recorded.
trace_entry_call <- function(entry) {
  if (!is.list(entry) || !is_string(entry$op)) {
    genui_abort("Malformed trace entry: expected a list with an {.field op} string.")
  }
  switch(entry$op,
    create = genui_call(
      entry$component,
      c(
        entry$args %||% list(),
        if (!is.null(entry$parent_id)) list(parent_id = entry$parent_id)
      )
    ),
    update = genui_call(
      "update_component",
      list(id = entry$id, args = entry$args %||% list())
    ),
    remove = genui_call("remove_component", list(id = entry$id)),
    clear = genui_call("clear_canvas"),
    genui_abort("Unknown trace op {.val {entry$op}}.")
  )
}
