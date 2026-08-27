`%||%` <- function(x, y) if (is.null(x)) y else x

#' Signal a shinygenui error
#'
#' All errors raised by this package carry the `genui_error` class so that
#' tool wrappers and tests can distinguish them. Errors raised while
#' validating a model-issued call additionally carry `genui_dispatch_error`;
#' their messages are written for the model to read and self-correct from.
#'
#' @noRd
genui_abort <- function(
  message,
  ...,
  class = character(),
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  cli::cli_abort(
    message,
    ...,
    class = c(class, "genui_error"),
    call = call,
    .envir = .envir
  )
}

dispatch_abort <- function(
  message,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  genui_abort(
    message,
    ...,
    class = "genui_dispatch_error",
    call = call,
    .envir = .envir
  )
}

is_ellmer_type <- function(x) {
  inherits(x, "ellmer::Type")
}

is_string <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x)
}

is_named_list <- function(x) {
  is.list(x) &&
    (length(x) == 0 ||
      (!is.null(names(x)) && all(nzchar(names(x))) && !anyDuplicated(names(x))))
}

reserved_tool_names <- function() {
  c("update_component", "remove_component", "clear_canvas", "get_canvas_state")
}

reserved_arg_names <- function() {
  c("id", "parent_id")
}

drop_nulls <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}
