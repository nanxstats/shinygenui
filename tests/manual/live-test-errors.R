# Live acceptance test B: error feedback loop (prompts scenario 4) with an
# ungrounded catalog. Column args are free-form strings; only the check()
# hooks validate against the live data, so a wrong column becomes a real
# tool error the model must read and recover from. Also exercises
# clear_canvas. Run from the package root:
# Rscript tests/manual/live-test-errors.R

stopifnot(file.exists("DESCRIPTION"))
readRenviron(".env")
stopifnot(nzchar(Sys.getenv("OPENAI_API_KEY")))
devtools::load_all(".", quiet = TRUE)

live_model <- Sys.getenv("SHINYGENUI_LIVE_MODEL", "gpt-5.6-sol")

pass <- function(ok, label) {
  cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "PASS" else "FAIL", label))
  if (!isTRUE(ok)) assign("failures", get("failures", globalenv()) + 1L, globalenv())
  invisible(ok)
}
failures <- 0L

# No data grounding: enums become strings; check() hooks are the only guard.
catalog <- genui_catalog(genui_components_bslib(data = NULL))

chat <- ellmer::chat_openai(
  model = live_model,
  params = ellmer::params(reasoning_effort = "medium"),
  echo = "none"
)

tool_errors <- function(chat) {
  out <- character()
  for (turn in chat$get_turns()) {
    for (content in attr(turn, "contents")) {
      if (inherits(content, "ellmer::ContentToolResult")) {
        err <- attr(content, "error")
        if (!is.null(err)) {
          out <- c(out, if (inherits(err, "condition")) conditionMessage(err) else err)
        }
      }
    }
  }
  out
}

shiny::testServer(
  genui_server,
  args = list(
    id = "genui",
    catalog = catalog,
    chat = chat,
    data = function() mtcars,
    system_prompt = genui_prompt(
      catalog,
      context = "The data is R's built-in mtcars dataset."
    )
  ),
  {
    say <- function(msg) {
      cat("\n=== USER:", msg, "\n")
      reply <- suppressWarnings(chat$chat(msg))
      cat("--- ASSISTANT:", format(reply), "\n")
      reply
    }
    types <- function() {
      vapply(engine$registry$snapshot()$instances, function(x) x$component, character(1))
    }

    # Force a check-hook failure: 'price' is not an mtcars column, and the
    # string schema will happily accept it.
    say(paste(
      "Add a histogram of the 'price' column.",
      "Call the histogram tool with column set exactly to 'price' first;",
      "only adjust if the tool rejects it."
    ))
    errors <- tool_errors(chat)
    cat("tool errors so far:\n")
    for (e in errors) cat("  *", gsub("\n", " ", e), "\n")
    pass(length(errors) >= 1, "S4: a tool error reached the model")
    pass(
      any(grepl("price", errors)) && any(grepl("Available columns", errors)),
      "S4: error names the bad column and lists available ones"
    )
    bad <- vapply(
      engine$registry$snapshot()$instances,
      function(x) identical(x$args$column, "price"),
      logical(1)
    )
    pass(!any(bad), "S4: no invalid instance reached the canvas")

    # Session must remain fully usable after the failure.
    say("OK, use horsepower instead.")
    pass("histogram" %in% types(), "S4: model recovered with a valid column")
    pass(
      all(vapply(
        engine$registry$snapshot()$instances,
        function(x) x$args$column %in% names(mtcars),
        logical(1)
      )),
      "S4: all canvas columns are real after recovery"
    )

    # clear_canvas built-in.
    say("Thanks. Clear the canvas.")
    pass(engine$registry$size() == 0L, "clear: canvas emptied")
    ops <- vapply(engine$registry$trace(), function(x) x$op, character(1))
    pass(identical(ops[length(ops)], "clear"), "clear: trace records the clear op")
  }
)

cat(sprintf("\n== error-loop live test: %d failure(s)\n", failures))
quit(status = if (failures > 0) 1L else 0L)
