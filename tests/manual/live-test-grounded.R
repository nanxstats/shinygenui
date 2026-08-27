# Live acceptance test A: grounded catalog on mtcars.
# Covers prompts scenarios 1-3 and 5, plus the get_canvas_state read-back.
# Run from the package root: Rscript tests/manual/live-test-grounded.R

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

catalog <- genui_catalog(genui_card_row(), genui_components_bslib(data = mtcars))
context <- paste(
  "The data is R's built-in mtcars dataset: 32 cars (1974 Motor Trend).",
  "Columns: mpg (miles per gallon), cyl (cylinders), disp (displacement),",
  "hp (horsepower), drat (rear axle ratio), wt (weight), qsec (quarter mile",
  "time), vs (engine shape), am (transmission), gear (gears), carb (carburetors)."
)

chat <- ellmer::chat_openai(
  model = live_model,
  params = ellmer::params(reasoning_effort = "medium"),
  echo = "none"
)

saved <- new.env(parent = emptyenv())

# Drain an async content stream through the later event loop, mimicking the
# in-app path where tool calls fire inside promise chains.
drain_stream <- function(stream, timeout = 300) {
  done <- FALSE
  err <- NULL
  text <- character()
  p <- coro::async(function() {
    for (chunk in coro::await_each(stream)) {
      if (inherits(chunk, "ellmer::ContentText")) {
        text <<- c(text, attr(chunk, "text"))
      }
    }
  })()
  promises::then(
    p,
    onFulfilled = function(...) done <<- TRUE,
    onRejected = function(e) {
      err <<- e
      done <<- TRUE
    }
  )
  start <- Sys.time()
  while (!done && difftime(Sys.time(), start, units = "secs") < timeout) {
    later::run_now(0.1)
  }
  if (!is.null(err)) stop(err)
  if (!done) stop("stream timed out")
  paste(text, collapse = "")
}

shiny::testServer(
  genui_server,
  args = list(
    id = "genui",
    catalog = catalog,
    chat = chat,
    data = function() mtcars,
    system_prompt = genui_prompt(catalog, context = context)
  ),
  {
    say <- function(msg) {
      cat("\n=== USER:", msg, "\n")
      reply <- suppressWarnings(chat$chat(msg))
      cat("--- ASSISTANT:", format(reply), "\n")
      reply
    }
    say_async <- function(msg) {
      cat("\n=== USER (async):", msg, "\n")
      reply <- suppressWarnings(
        drain_stream(chat$stream_async(msg, stream = "content"))
      )
      cat("--- ASSISTANT:", reply, "\n")
      reply
    }
    snap <- function() engine$registry$snapshot()$instances
    types <- function() vapply(snap(), function(x) x$component, character(1))
    show_state <- function() {
      for (id in names(snap())) {
        inst <- snap()[[id]]
        cat(sprintf(
          "  %s: %s(%s)%s\n",
          id,
          inst$component,
          paste(names(inst$args), unlist(lapply(inst$args, paste, collapse = "|")), sep = "=", collapse = ", "),
          if (!is.null(inst$parent_id)) paste0(" in ", inst$parent_id) else ""
        ))
      }
    }

    # Scenario 1: two components in one turn -------------------------------
    say("Show mpg vs. hp, and a value box with the average mpg.")
    show_state()
    pass("scatter_plot" %in% types(), "S1: scatter_plot created")
    pass("value_box" %in% types(), "S1: value_box created")
    scatter_id <- names(types())[types() == "scatter_plot"][1]
    box_id <- names(types())[types() == "value_box"][1]

    # Scenario 2: update in place + remove ---------------------------------
    say("Color the scatter by cylinders and drop the value box.")
    show_state()
    pass(
      scatter_id %in% names(snap()) &&
        identical(snap()[[scatter_id]]$component, "scatter_plot"),
      "S2: scatter kept its instance id (updated in place)"
    )
    pass(
      identical(snap()[[scatter_id]]$args$color, "cyl"),
      "S2: scatter color arg is cyl"
    )
    pass(!box_id %in% names(snap()), "S2: value_box removed")
    ops <- vapply(engine$registry$trace(), function(x) x$op, character(1))
    pass("update" %in% ops, "S2: trace has an update op (no duplicate create)")

    # Scenario 3 (async path): interactive histogram ------------------------
    say_async("Add a histogram of hp.")
    show_state()
    hist_id <- names(types())[types() == "histogram"]
    pass(length(hist_id) == 1, "S3: histogram created via async stream")
    if (length(hist_id) == 1) {
      html <- as.character(
        catalog$histogram$ui(session$ns(hist_id), snap()[[hist_id]]$args)
      )
      pass(
        grepl(paste0(session$ns(hist_id), "-bins"), html, fixed = TRUE),
        "S3: histogram ui embeds the bins slider"
      )
      # embedded slider value round trip, then the model reads it back
      do.call(session$setInputs, stats::setNames(list(42L), paste0(hist_id, "-bins")))
      reply <- say("What number of bins is the hp histogram currently set to?")
      pass(grepl("42", format(reply)), "S3: model read embedded input via get_canvas_state")
    }

    saved$trace <- engine$registry$trace()
    saved$instances <- snap()
  }
)

# Scenario 5: replay in a fresh session, no LLM ---------------------------
shiny::testServer(
  function(input, output, session) {
    saved$handles <- suppressWarnings(
      genui_replay(saved$trace, catalog, target = "mirror", data = function() mtcars)
    )
  },
  {
    replayed <- shiny::isolate(saved$handles$instances())
    pass(
      identical(replayed, saved$instances),
      "S5: replay reproduces the final canvas exactly"
    )
  }
)

cat(sprintf("\n== grounded live test: %d failure(s)\n", failures))
quit(status = if (failures > 0) 1L else 0L)
