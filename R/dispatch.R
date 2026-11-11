#' Create a normalized tool call
#'
#' A `genui_call` is the normalized representation of one model-issued tool
#' call: the tool name plus its arguments as plain data. [genui_dispatch()]
#' consumes these. In production they are produced by the compiled ellmer
#' tools; in tests and replays you can hand-build them.
#'
#' @param tool Tool name: a component name from the catalog, or one of the
#'   built-ins `"update_component"`, `"remove_component"`, `"clear_canvas"`.
#' @param args Named list of arguments as plain data, such as the model's
#'   JSON arguments after parsing. An array may be an atomic vector or an
#'   unnamed list. For `update_component`, `args` must contain `id` and
#'   `args` (the arguments to replace, as a named list or a JSON object
#'   string).
#'
#' @return A `genui_call` object.
#' @export
#' @examples
#' genui_call("scatter_plot", list(x = "mpg", y = "hp"))
#' genui_call("update_component", list(id = "c1", args = list(x = "wt")))
#' genui_call("remove_component", list(id = "c1"))
genui_call <- function(tool, args = list()) {
  if (!is_string(tool)) {
    genui_abort("{.arg tool} must be a single string.")
  }
  if (!is.list(args) || (length(args) > 0 && !is_named_list(args))) {
    genui_abort("{.arg args} must be a named list.")
  }
  structure(list(tool = tool, args = args), class = "genui_call")
}

as_genui_call <- function(call, error_call = rlang::caller_env()) {
  if (inherits(call, "genui_call")) {
    return(call)
  }
  if (is.list(call) && is_string(call[["tool"]])) {
    return(genui_call(call$tool, call[["args"]] %||% list()))
  }
  genui_abort(
    "{.arg call} must be a {.cls genui_call} object, or a list with elements {.field tool} and {.field args}.",
    call = error_call
  )
}

as_genui_state <- function(state, error_call = rlang::caller_env()) {
  if (inherits(state, "GenuiRegistry")) {
    return(state$snapshot())
  }
  if (!is.list(state)) {
    genui_abort(
      "{.arg state} must be a {.cls GenuiRegistry} or a list with elements {.field instances} and {.field next_id}.",
      call = error_call
    )
  }
  instances <- state$instances %||% list()
  next_id <- state$next_id %||% (max(c(0L, instance_id_numbers(names(instances)))) + 1L)
  list(instances = instances, next_id = next_id)
}

instance_id_numbers <- function(ids) {
  nums <- suppressWarnings(as.integer(sub("^c", "", ids)))
  nums[!is.na(nums)]
}

#' Validate one tool call and plan its effect
#'
#' The pure core of shinygenui: given the catalog, one normalized call, and
#' the current instance state, either return a plan describing what should
#' happen (create, update, remove, or clear) or signal a classed error whose
#' message is written for the model to read and correct. No Shiny session,
#' registry mutation, or LLM is involved; the Shiny executor applies the
#' returned plan.
#'
#' @param catalog A [genui_catalog()].
#' @param call A [genui_call()] (or a plain list with `tool` and `args`).
#' @param state Current instance state: a `GenuiRegistry` or a list with
#'   `instances` (a named list of `list(component, args, parent_id)` keyed by
#'   instance id) and `next_id` (integer).
#' @param data Current value of the app's data object, passed to component
#'   `check()` hooks. Typically `shiny::isolate(data())` at call time.
#'
#' @return A `genui_plan` object, a list with at least `action` (one of
#'   `"create"`, `"update"`, `"remove"`, `"clear"`) plus the fields the
#'   executor needs: `id`, `component`, `args` (full args to render),
#'   `delta` (validated partial args, updates only), `parent_id`, and `ids`
#'   (teardown order, removes and clears only). Argument values in `args`
#'   and `delta` use the form described in the "Argument values" section of
#'   [genui_component()].
#' @export
#' @examples
#' catalog <- genui_catalog(
#'   genui_component(
#'     name = "note_card",
#'     description = "A card showing a short note.",
#'     args = list(text = "The note text."),
#'     ui = function(id, args) htmltools::p(args$text)
#'   )
#' )
#' state <- list(instances = list(), next_id = 1L)
#' genui_dispatch(catalog, genui_call("note_card", list(text = "hi")), state)
genui_dispatch <- function(catalog, call, state, data = NULL) {
  check_catalog(catalog)
  call <- as_genui_call(call)
  state <- as_genui_state(state)

  switch(call[["tool"]],
    update_component = dispatch_update(catalog, call[["args"]], state, data),
    remove_component = dispatch_remove(call[["args"]], state),
    clear_canvas = dispatch_clear(state),
    dispatch_create(catalog, call[["tool"]], call[["args"]], state, data)
  )
}

new_plan <- function(action, ...) {
  structure(list(action = action, ...), class = "genui_plan")
}

# Create -----------------------------------------------------------------

dispatch_create <- function(catalog, name, args, state, data) {
  component <- catalog_get(catalog, name)
  if (is.null(component)) {
    dispatch_abort(c(
      "Unknown tool or component {.val {name}}.",
      i = "Available components: {.val {names(catalog)}}."
    ))
  }

  parent_id <- args[["parent_id"]]
  args[["parent_id"]] <- NULL
  if (!is.null(parent_id)) {
    parent_id <- check_parent(catalog, parent_id, state)
  }

  args <- validate_component_args(component, args, complete = TRUE)
  run_check_hook(component, args, data)

  new_plan(
    "create",
    id = paste0("c", state$next_id),
    component = component$name,
    args = args,
    parent_id = parent_id
  )
}

check_parent <- function(catalog, parent_id, state) {
  parent_id <- unwrap_scalar(parent_id)
  if (!is_string(parent_id)) {
    dispatch_abort("{.arg parent_id} must be a single instance id string, like {.val c1}.")
  }
  parent <- state$instances[[parent_id]]
  if (is.null(parent)) {
    dispatch_abort(c(
      "No component instance with id {.val {parent_id}} to place this component into.",
      i = describe_instances(state)
    ))
  }
  parent_component <- catalog_get(catalog, parent$component)
  if (is.null(parent_component) || !isTRUE(parent_component$container)) {
    dispatch_abort(
      "Instance {.val {parent_id}} ({.val {parent$component}}) is not a container; only container components can hold children."
    )
  }
  parent_id
}

# Update -----------------------------------------------------------------

dispatch_update <- function(catalog, cargs, state, data) {
  id <- check_instance_id(cargs[["id"]], state, verb = "update")
  instance <- state$instances[[id]]

  component <- catalog_get(catalog, instance$component)
  if (is.null(component)) {
    dispatch_abort(
      "Component {.val {instance$component}} of instance {.val {id}} is no longer in the catalog, so it cannot be updated."
    )
  }

  delta <- parse_update_args(cargs[["args"]])
  if ("parent_id" %in% names(delta)) {
    dispatch_abort(
      "{.arg parent_id} cannot be changed by {.code update_component}; remove the component and create a new one instead."
    )
  }

  # Validate the provided (non-null) part of the delta; a JSON null value
  # means "reset this argument to its default" and is applied by the merge.
  provided <- validate_component_args(
    component,
    drop_nulls(delta),
    complete = FALSE
  )
  delta[names(provided)] <- provided
  # Each supplied argument replaces the stored value as a whole. Arrays and
  # objects are never merged element by element.
  merged <- instance$args
  merged[names(delta)] <- delta
  merged <- validate_component_args(component, merged, complete = TRUE)
  run_check_hook(component, merged, data)

  new_plan(
    "update",
    id = id,
    component = instance$component,
    args = merged,
    delta = delta,
    parent_id = instance$parent_id
  )
}

parse_update_args <- function(args) {
  if (is.null(args)) {
    return(list())
  }
  args <- unwrap_scalar(args)
  if (is_string(args)) {
    # No simplification: arrays stay lists, as in the arguments ellmer passes
    # to the component tools, so both paths share one normalization.
    parsed <- tryCatch(
      jsonlite::fromJSON(args, simplifyVector = FALSE),
      error = function(e) {
        dispatch_abort(c(
          "{.arg args} is not valid JSON.",
          i = "Pass a JSON object string mapping argument names to new values, like {.code {{\"x\": \"hp\"}}}."
        ))
      }
    )
    args <- as.list(parsed %||% list())
  }
  if (!is.list(args) || (length(args) > 0 && !is_named_list(args))) {
    dispatch_abort(
      "{.arg args} must be a JSON object (or named list) mapping argument names to new values."
    )
  }
  args
}

# Remove and clear -------------------------------------------------------

dispatch_remove <- function(cargs, state) {
  id <- check_instance_id(cargs[["id"]], state, verb = "remove")
  ids <- c(instance_descendants(state$instances, id), id)
  new_plan("remove", id = id, ids = ids)
}

dispatch_clear <- function(state) {
  roots <- names(state$instances)[
    vapply(state$instances, function(x) is.null(x$parent_id), logical(1))
  ]
  ids <- unlist(lapply(roots, function(root) {
    c(instance_descendants(state$instances, root), root)
  }))
  new_plan("clear", ids = as.character(ids %||% character()))
}

check_instance_id <- function(id, state, verb, call = rlang::caller_env()) {
  id <- unwrap_scalar(id)
  if (!is_string(id)) {
    dispatch_abort(
      "{.arg id} must be a single instance id string, like {.val c1}.",
      call = call
    )
  }
  if (is.null(state$instances[[id]])) {
    dispatch_abort(
      c(
        "No component instance with id {.val {id}} to {verb}.",
        i = describe_instances(state)
      ),
      call = call
    )
  }
  id
}

describe_instances <- function(state) {
  if (length(state$instances) == 0) {
    return("The canvas is currently empty.")
  }
  labels <- vapply(
    names(state$instances),
    function(id) sprintf("%s (%s)", id, state$instances[[id]]$component),
    character(1)
  )
  cli::format_inline("Current instances: {.val {labels}}.")
}

# Children of `id`, deepest first, so teardown can run leaf to root.
instance_descendants <- function(instances, id) {
  children <- names(instances)[
    vapply(instances, function(x) identical(x$parent_id, id), logical(1))
  ]
  out <- character()
  for (child in children) {
    out <- c(out, instance_descendants(instances, child), child)
  }
  out
}

# Argument validation ----------------------------------------------------

# Validates `args` against a component's declared ellmer types and returns
# the cleaned list: NULL values dropped and every value in the canonical form
# described at validate_arg_value(). With `complete = TRUE`, required
# arguments must all be present.
validate_component_args <- function(component, args, complete = TRUE) {
  if (length(args) > 0 && !is_named_list(args)) {
    dispatch_abort(
      "Arguments for {.val {component$name}} must be supplied as a named list with unique names."
    )
  }
  args <- drop_nulls(args)
  declared <- component$args

  unknown <- setdiff(names(args), names(declared))
  if (length(unknown) > 0) {
    dispatch_abort(c(
      "{cli::qty(length(unknown))}Unknown argument{?s} {.val {unknown}} for component {.val {component$name}}.",
      i = if (length(declared) > 0) {
        cli::format_inline("Declared arguments: {.val {names(declared)}}.")
      } else {
        cli::format_inline("{.val {component$name}} takes no arguments.")
      }
    ))
  }

  if (complete) {
    required <- names(declared)[vapply(
      declared,
      function(type) isTRUE(attr(type, "required", exact = TRUE)),
      logical(1)
    )]
    missing <- setdiff(required, names(args))
    if (length(missing) > 0) {
      dispatch_abort(
        "{cli::qty(length(missing))}Missing required argument{?s} {.val {missing}} for component {.val {component$name}}."
      )
    }
  }

  for (nm in names(args)) {
    args[nm] <- list(
      validate_arg_value(declared[[nm]], args[[nm]], nm, component$name)
    )
  }
  args
}

# Validates one value against its declared type and returns it in canonical
# form. Values arrive as plain data in either spelling: parsed from JSON
# (every array is an unnamed list) or written in R (arrays of scalars are
# atomic vectors). Components, the registry, and the trace only ever see the
# canonical form:
#
# - string, enum, boolean, integer, number: a length-one vector
# - array of those: an atomic vector, possibly empty
# - any other array: an unnamed list of canonical items
# - object: a named list of canonical fields, without NULL fields
validate_arg_value <- function(type, value, arg, component) {
  if (inherits(type, "ellmer::TypeEnum")) {
    value <- unwrap_scalar(value)
    values <- attr(type, "values", exact = TRUE)
    if (!is_string(value) || !value %in% values) {
      shown <- describe_value(value)
      dispatch_abort(c(
        "Invalid value {shown} for argument {.val {arg}} of {.val {component}}.",
        i = "Must be one of {.val {values}}."
      ))
    }
  } else if (inherits(type, "ellmer::TypeBasic")) {
    value <- unwrap_scalar(value)
    kind <- attr(type, "type", exact = TRUE)
    ok <- switch(kind,
      string = is_string(value),
      boolean = is.logical(value) && length(value) == 1 && !is.na(value),
      integer = is.numeric(value) &&
        length(value) == 1 &&
        !is.na(value) &&
        value == trunc(value),
      number = is.numeric(value) && length(value) == 1 && !is.na(value),
      TRUE
    )
    if (!ok) {
      shown <- describe_value(value)
      dispatch_abort(
        "Argument {.val {arg}} of {.val {component}} must be a single {kind} value, not {shown}."
      )
    }
  } else if (inherits(type, "ellmer::TypeArray")) {
    items <- attr(type, "items", exact = TRUE)
    bad_shape <- is.null(value) ||
      !(is.atomic(value) || is.list(value)) ||
      (is.list(value) && !is.null(names(value)))
    if (bad_shape) {
      dispatch_abort(
        "Argument {.val {arg}} of {.val {component}} must be an array of values."
      )
    }
    value <- lapply(unname(as.list(value)), function(item) {
      validate_arg_value(items, item, arg, component)
    })
    empty <- scalar_prototype(items)
    if (!is.null(empty)) {
      value <- unlist(value, use.names = FALSE) %||% empty
    }
  } else if (inherits(type, "ellmer::TypeObject")) {
    properties <- attr(type, "properties", exact = TRUE)
    if (!is_named_list(value)) {
      dispatch_abort(
        "Argument {.val {arg}} of {.val {component}} must be an object with named fields."
      )
    }
    # As at the top level, a null field is an absent field.
    value <- drop_nulls(value)
    unknown <- setdiff(names(value), names(properties))
    if (length(unknown) > 0) {
      dispatch_abort(c(
        "{cli::qty(length(unknown))}Unknown field{?s} {.val {unknown}} in argument {.val {arg}} of {.val {component}}.",
        i = "Declared fields: {.val {names(properties)}}."
      ))
    }
    required <- names(properties)[vapply(
      properties,
      function(p) isTRUE(attr(p, "required", exact = TRUE)),
      logical(1)
    )]
    missing <- setdiff(required, names(value))
    if (length(missing) > 0) {
      dispatch_abort(
        "{cli::qty(length(missing))}Missing required field{?s} {.val {missing}} in argument {.val {arg}} of {.val {component}}."
      )
    }
    for (nm in names(value)) {
      value[nm] <- list(
        validate_arg_value(properties[[nm]], value[[nm]], arg, component)
      )
    }
  }
  # Other type kinds (for example, raw JSON schemas) pass through untouched.
  # Nothing here can validate them, and not every provider enforces the
  # declared schema, so such a component should verify the value in check().
  value
}

# Some models wrap a scalar in a one-element JSON array. ellmer's argument
# conversion unwraps it. The tools opt out of that conversion, so the same
# tolerance lives here, for component arguments and for the ids and `args`
# string of the built-in tools.
unwrap_scalar <- function(value) {
  if (is.list(value) && length(value) == 1 && is.null(names(value))) {
    value[[1]]
  } else {
    value
  }
}

# The empty atomic vector that an array of `type` simplifies to, or NULL
# when values of `type` are not scalars and an array of them stays a list.
scalar_prototype <- function(type) {
  if (inherits(type, "ellmer::TypeEnum")) {
    character()
  } else if (inherits(type, "ellmer::TypeBasic")) {
    switch(attr(type, "type", exact = TRUE),
      string = character(),
      boolean = logical(),
      integer = integer(),
      number = numeric()
    )
  }
}

# A rejected value as the model wrote it: compact JSON, so that nulls,
# arrays, and objects keep their shape. The text is model-supplied; only
# ever interpolate it into a message as a single value.
describe_value <- function(value) {
  tryCatch(
    to_json_compact(value),
    error = function(e) "a value that is not plain data"
  )
}

run_check_hook <- function(component, args, data) {
  if (is.null(component$check)) {
    return(invisible())
  }
  result <- component$check(args, data)
  if (is.character(result) && any(nzchar(result))) {
    message <- paste(result[nzchar(result)], collapse = " ")
    dispatch_abort("Invalid arguments for {.val {component$name}}: {message}")
  }
  invisible()
}
