#' Define a generative UI component
#'
#' A component is one entry in the finite catalog that constrains what the
#' model can render. It couples a model-facing tool schema (`name`,
#' `description`, typed `args`) with developer-written rendering code: a
#' `ui` function plus an optional `server` function, instantiated together
#' as a dynamic Shiny module every time the model creates or updates an
#' instance. The model only ever supplies data arguments validated against
#' the declared types; it never emits code.
#'
#' @param name Tool name the model sees. A snake_case string: lowercase
#'   letters, digits, and underscores, starting with a letter. Must be unique
#'   within a catalog and must not collide with the built-in lifecycle tools
#'   (`update_component`, `remove_component`, `clear_canvas`).
#' @param description One to three sentences telling the model what the
#'   component shows and when to use it. This is the model-facing
#'   documentation for the component, so write it well.
#' @param args Named list of ellmer type specifications
#'   (for example [ellmer::type_string()], [ellmer::type_enum()]) describing
#'   the arguments the model may supply. As a shorthand, a plain string is
#'   promoted to `ellmer::type_string(<string>)`. Argument names `id` and
#'   `parent_id` are reserved by the package. Catalogs are often built inside
#'   the Shiny server function so enums can enumerate live facts, such as the
#'   column names of the active dataset.
#' @param ui `function(id, args)` returning an [htmltools::tag()] (or tag
#'   list). `id` is the fully namespaced module id for this instance; use
#'   `shiny::NS(id)` to namespace any embedded inputs and outputs. `args` is
#'   the validated argument list.
#' @param server Optional `function(id, args, data)` that calls
#'   [shiny::moduleServer()] to wire outputs and embedded inputs. `data` is
#'   the reactive passed to [genui_server()]. If the module creates
#'   observers, include them in the module's return value (alone or inside a
#'   list) so the package can destroy them when the instance is updated or
#'   removed. A `reactives` element in the return value is stored in the
#'   instance registry keyed by instance id; nothing reads it in v0.1, it is
#'   the hook for cross-component reactivity in a later release.
#' @param check Optional `function(args, data)` for semantic validation
#'   beyond the JSON schema. Return `NULL` when `args` are acceptable, or a
#'   string describing the problem; the string is returned to the model as a
#'   tool error so it can self-correct.
#' @param container If `TRUE`, this component can host child instances: its
#'   `ui` must render an element with id `shiny::NS(id, "slot")`, and other
#'   components may target it by passing the instance's id as `parent_id`.
#' @param width Layout hint for the canvas grid: `"auto"` (default),
#'   `"wide"`, or `"full"`.
#'
#' @return A `genui_component` object.
#' @export
#' @examples
#' genui_component(
#'   name = "note_card",
#'   description = "A card showing a short markdown note. Use for narrative
#'     text that should live on the canvas rather than in the chat.",
#'   args = list(
#'     title = "A short title for the card.",
#'     text = ellmer::type_string("The markdown body text.")
#'   ),
#'   ui = function(id, args) {
#'     htmltools::div(
#'       htmltools::h5(args$title),
#'       htmltools::p(args$text)
#'     )
#'   }
#' )
genui_component <- function(
  name,
  description,
  args = list(),
  ui,
  server = NULL,
  check = NULL,
  container = FALSE,
  width = c("auto", "wide", "full")
) {
  if (!is_string(name) || !grepl("^[a-z][a-z0-9_]*$", name)) {
    genui_abort(
      "{.arg name} must be a snake_case string: lowercase letters, digits, and underscores, starting with a letter."
    )
  }
  if (name %in% reserved_tool_names()) {
    genui_abort(
      "{.val {name}} is reserved for a built-in lifecycle tool; pick another component name."
    )
  }
  if (!is_string(description) || !nzchar(trimws(description))) {
    genui_abort("{.arg description} must be a non-empty string.")
  }

  args <- normalize_arg_types(args, name)

  check_component_fn(ui, "ui", c("id", "args"))
  if (!is.null(server)) {
    check_component_fn(server, "server", c("id", "args", "data"))
  }
  if (!is.null(check)) {
    check_component_fn(check, "check", c("args", "data"))
  }
  if (!is.logical(container) || length(container) != 1 || is.na(container)) {
    genui_abort("{.arg container} must be `TRUE` or `FALSE`.")
  }
  width <- match.arg(width)

  structure(
    list(
      name = name,
      description = description,
      args = args,
      ui = ui,
      server = server,
      check = check,
      container = isTRUE(container),
      width = width
    ),
    class = "genui_component"
  )
}

normalize_arg_types <- function(args, name, call = rlang::caller_env()) {
  if (length(args) == 0) {
    return(list())
  }
  if (!is_named_list(args)) {
    genui_abort(
      "{.arg args} must be a named list of ellmer types with unique names.",
      call = call
    )
  }

  bad_names <- names(args)[!grepl("^[a-zA-Z][a-zA-Z0-9_]*$", names(args))]
  if (length(bad_names) > 0) {
    genui_abort(
      "{cli::qty(length(bad_names))}Invalid argument name{?s} {.val {bad_names}} for component {.val {name}}.",
      call = call
    )
  }
  reserved <- intersect(names(args), reserved_arg_names())
  if (length(reserved) > 0) {
    genui_abort(
      "{cli::qty(length(reserved))}Argument name{?s} {.val {reserved}} {?is/are} reserved by shinygenui and cannot be declared by component {.val {name}}.",
      call = call
    )
  }

  args <- lapply(args, function(x) {
    if (is_string(x)) ellmer::type_string(x) else x
  })
  ok <- vapply(args, is_ellmer_type, logical(1))
  if (!all(ok)) {
    genui_abort(
      c(
        "All {.arg args} of component {.val {name}} must be ellmer type specifications.",
        i = "Problem with argument{?s} {.val {names(args)[!ok]}}; use {.fn ellmer::type_string}, {.fn ellmer::type_enum}, and friends."
      ),
      call = call
    )
  }
  args
}

check_component_fn <- function(fn, what, arg_names, call = rlang::caller_env()) {
  if (!is.function(fn)) {
    genui_abort(
      "{.arg {what}} must be a function with arguments {.arg {arg_names}}.",
      call = call
    )
  }
  fmls <- names(formals(fn))
  if ("..." %in% fmls) {
    return(invisible(fn))
  }
  if (length(fmls) < length(arg_names)) {
    genui_abort(
      "{.arg {what}} must accept {length(arg_names)} argument{?s}: {.arg {arg_names}}.",
      call = call
    )
  }
  invisible(fn)
}

#' @export
print.genui_component <- function(x, ...) {
  cli::cli_text("<genui_component> {.val {x$name}}")
  cli::cli_text("  {x$description}")
  if (length(x$args) > 0) {
    cli::cli_text("  args: {.val {names(x$args)}}")
  } else {
    cli::cli_text("  args: none")
  }
  if (isTRUE(x$container)) {
    cli::cli_text("  container: yes")
  }
  invisible(x)
}
