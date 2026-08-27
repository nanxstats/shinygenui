# The Shiny executor: applies plans from genui_dispatch() to a live session.
#
# One engine per genui_server() (and per genui_replay()) call. It owns the
# session-scoped registry and performs all DOM work. Tool implementations
# close over the engine; because tool calls fire inside ellmer's async
# promise chains where the ambient reactive domain is unreliable, every
# insertUI()/removeUI() gets `session` explicitly, and component servers run
# under shiny::withReactiveDomain() so moduleServer() binds to the right
# scope.
GenuiEngine <- R6::R6Class(
  "GenuiEngine",
  public = list(
    registry = NULL,

    initialize = function(catalog, session, data = NULL) {
      check_catalog(catalog)
      private$catalog <- catalog
      private$session <- session
      private$data <- data %||% function() NULL
      self$registry <- GenuiRegistry$new()
    },

    # Full pipeline for one model-issued call: validate + plan, execute
    # against the DOM and registry, and describe the outcome to the model.
    # Errors (validation or rendering) propagate; ellmer converts them into
    # tool errors for the model, and the session never sees them. Failures
    # are logged on the way out without being caught.
    handle = function(call) {
      call <- as_genui_call(call)
      withCallingHandlers(
        {
          plan <- genui_dispatch(
            private$catalog,
            call,
            self$registry,
            data = private$current_data()
          )
          self$execute(plan)
          log_plan(plan)
          plan_tool_result(plan)
        },
        error = function(e) log_failure(call, e)
      )
    },

    execute = function(plan) {
      switch(
        plan$action,
        create = private$execute_create(plan),
        update = private$execute_update(plan),
        remove = private$execute_remove(plan),
        clear = private$execute_clear(plan),
        genui_abort("Unknown plan action {.val {plan$action}}.")
      )
      invisible(plan)
    }
  ),
  private = list(
    catalog = NULL,
    session = NULL,
    data = NULL,

    current_data = function() {
      if (is.function(private$data)) {
        shiny::isolate(private$data())
      } else {
        private$data
      }
    },

    canvas_selector = function() {
      paste0("#", private$session$ns("canvas"))
    },

    shell_dom_id = function(id) {
      private$session$ns(paste0("shell-", id))
    },

    target_selector = function(parent_id) {
      if (is.null(parent_id)) {
        private$canvas_selector()
      } else {
        # Containers render a slot element with id NS(<module id>, "slot").
        paste0("#", private$session$ns(paste0(parent_id, "-slot")))
      }
    },

    build_shell = function(component, plan) {
      htmltools::div(
        id = private$shell_dom_id(plan$id),
        class = paste0("genui-shell genui-width-", component$width),
        `data-genui-component` = component$name,
        component$ui(private$session$ns(plan$id), plan$args)
      )
    },

    run_component_server = function(component, plan) {
      if (is.null(component$server)) {
        return(NULL)
      }
      shiny::withReactiveDomain(
        private$session,
        component$server(plan$id, plan$args, private$data)
      )
    },

    execute_create = function(plan) {
      component <- catalog_get(private$catalog, plan$component)
      shell <- private$build_shell(component, plan)
      shiny::insertUI(
        selector = private$target_selector(plan$parent_id),
        where = "beforeEnd",
        ui = shell,
        immediate = TRUE,
        session = private$session
      )
      handles <- tryCatch(
        private$run_component_server(component, plan),
        error = function(e) {
          # Keep DOM and registry consistent: a failed module never leaves a
          # half-rendered shell behind, and the error goes back to the model.
          shiny::removeUI(
            selector = paste0("#", private$shell_dom_id(plan$id)),
            immediate = TRUE,
            session = private$session
          )
          stop(e)
        }
      )
      self$registry$apply(plan)
      self$registry$set_handles(plan$id, handles)
    },

    execute_update = function(plan) {
      component <- catalog_get(private$catalog, plan$component)
      # Building the new UI first means arg-dependent render errors leave the
      # existing instance untouched.
      ui <- component$ui(private$session$ns(plan$id), plan$args)
      # Destroys the old observers (held in the registry), records the merged
      # args, and appends the trace entry.
      self$registry$apply(plan)
      shell_selector <- paste0("#", private$shell_dom_id(plan$id))
      shiny::removeUI(
        selector = paste0(shell_selector, " > *"),
        multiple = TRUE,
        immediate = TRUE,
        session = private$session
      )
      shiny::insertUI(
        selector = shell_selector,
        where = "beforeEnd",
        ui = ui,
        immediate = TRUE,
        session = private$session
      )
      # Same module id as before: outputs re-register over the old ones, and
      # embedded inputs come back at their defaults (documented v0.1
      # semantics).
      handles <- private$run_component_server(component, plan)
      self$registry$set_handles(plan$id, handles)
    },

    execute_remove = function(plan) {
      self$registry$apply(plan)
      # Children live inside the parent shell, so removing the top shell
      # removes the whole subtree; observers were destroyed leaf-first by the
      # registry.
      shiny::removeUI(
        selector = paste0("#", private$shell_dom_id(plan$id)),
        immediate = TRUE,
        session = private$session
      )
    },

    execute_clear = function(plan) {
      self$registry$apply(plan)
      shiny::removeUI(
        selector = paste0(private$canvas_selector(), " > .genui-shell"),
        multiple = TRUE,
        immediate = TRUE,
        session = private$session
      )
    }
  )
)

# Describe an executed plan to the model. The instance id is load-bearing:
# it is how the model addresses the component in later update/remove calls.
plan_tool_result <- function(plan) {
  value <- switch(
    plan$action,
    create = sprintf(
      "Created component instance \"%s\" (%s)%s. Refer to it by id \"%s\" in update_component or remove_component.",
      plan$id,
      plan$component,
      if (!is.null(plan$parent_id)) sprintf(" inside container \"%s\"", plan$parent_id) else "",
      plan$id
    ),
    update = sprintf(
      "Updated instance \"%s\" (%s) in place. Current arguments: %s",
      plan$id,
      plan$component,
      to_json_compact(plan$args)
    ),
    remove = if (length(plan$ids) > 1) {
      sprintf(
        "Removed instance \"%s\" and its %d child instance(s) (%s).",
        plan$id,
        length(plan$ids) - 1L,
        paste(setdiff(plan$ids, plan$id), collapse = ", ")
      )
    } else {
      sprintf("Removed instance \"%s\".", plan$id)
    },
    clear = if (length(plan$ids) > 0) {
      sprintf("Cleared the canvas; removed %d instance(s).", length(plan$ids))
    } else {
      "The canvas was already empty."
    }
  )

  title <- switch(
    plan$action,
    create = sprintf("Canvas: added %s", plan$component),
    update = sprintf("Canvas: updated %s", plan$id),
    remove = sprintf("Canvas: removed %s", plan$id),
    clear = "Canvas: cleared"
  )

  ellmer::ContentToolResult(
    value = value,
    extra = list(
      display = list(
        title = title,
        markdown = value,
        show_request = FALSE,
        open = FALSE
      )
    )
  )
}

to_json_compact <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
}
