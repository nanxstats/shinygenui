# Session logging. Failures are always logged (they end up in app server
# logs, e.g. on Posit Connect, where they are the main debugging signal);
# successful canvas operations are logged only when
# options(shinygenui.verbose = TRUE).
#
# Messages are pre-composed with sprintf() and interpolated as values so
# model-supplied text (which may contain braces or JSON) never reaches the
# cli interpolator.

genui_verbose <- function() {
  isTRUE(getOption("shinygenui.verbose", FALSE))
}

log_plan <- function(plan) {
  if (!genui_verbose()) {
    return(invisible())
  }
  message <- switch(plan$action,
    create = sprintf(
      "create %s (%s)%s",
      plan$id,
      plan$component,
      if (!is.null(plan$parent_id)) paste0(" in ", plan$parent_id) else ""
    ),
    update = sprintf("update %s (%s)", plan$id, plan$component),
    remove = sprintf(
      "remove %s%s",
      plan$id,
      if (length(plan$ids) > 1) {
        sprintf(" (+%d children)", length(plan$ids) - 1L)
      } else {
        ""
      }
    ),
    clear = sprintf("clear (%d instances)", length(plan$ids))
  )
  cli::cli_inform(c("i" = "[shinygenui] {message}"))
  invisible()
}

log_failure <- function(call, error) {
  message <- sprintf(
    "%s call failed: %s",
    call$tool,
    conditionMessage(error)
  )
  cli::cli_inform(c("x" = "[shinygenui] {message}"))
  invisible()
}
