engine_module <- function(id, catalog, data = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    engine <- shinygenui:::GenuiEngine$new(catalog, session = session, data = data)
    engine
  })
}

test_that("genui_trace exposes the trace reactive from the session store", {
  chat <- ellmer::chat_openai(
    model = "gpt-5.6-sol",
    credentials = function() list(api_key = "not-a-real-key")
  )
  shiny::testServer(
    genui_server,
    args = list(id = "genui", catalog = test_catalog(), chat = chat),
    {
      tools <- chat$get_tools()
      suppressWarnings(tools$value_box(title = "A", column = "mpg"))

      trace <- genui_trace(session)
      expect_true(is.function(trace))
      entries <- trace()
      expect_length(entries, 1)
      expect_identical(entries[[1]]$op, "create")
      expect_identical(entries[[1]]$component, "value_box")

      # explicit id works too, relative to the caller
      expect_length(genui_trace(session, id = "genui")(), 1)
      expect_error(genui_trace(session, id = "nope"), class = "genui_error")
    }
  )
})

test_that("genui_trace fails clearly with no canvas", {
  shiny::testServer(
    function(input, output, session) NULL,
    {
      expect_error(genui_trace(session), "genui_server", class = "genui_error")
    }
  )
})

test_that("card_row hosts children end to end", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("DT")
  catalog <- genui_catalog(genui_card_row(), genui_components_bslib(mtcars))
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = catalog, data = function() mtcars),
    {
      suppressWarnings({
        engine$handle(genui_call("card_row", list(title = "KPIs")))
        engine$handle(genui_call(
          "value_box",
          list(title = "Avg MPG", column = "mpg", agg = "mean", parent_id = "c1")
        ))
        engine$handle(genui_call(
          "value_box",
          list(title = "Max WT", column = "wt", agg = "max", parent_id = "c1")
        ))
      })
      expect_identical(engine$registry$get("c2")$parent_id, "c1")
      expect_identical(engine$registry$ids(), c("c1", "c2", "c3"))

      # the row's ui renders the slot the children were inserted into
      slot_html <- as.character(
        catalog$card_row$ui("genui-c1", list(title = "KPIs"))
      )
      expect_match(slot_html, 'id="genui-c1-slot"', fixed = TRUE)

      # removing the row cascades to its children
      suppressWarnings(
        engine$handle(genui_call("remove_component", list(id = "c1")))
      )
      expect_identical(engine$registry$size(), 0L)
    }
  )
})

test_that("replay rebuilds the canvas from a saved trace without an LLM", {
  catalog <- test_catalog()
  saved <- new.env(parent = emptyenv())

  # Session one: build a canvas the interesting way (container, child,
  # update, remove) and save its trace, like saveRDS() would.
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = catalog, data = function() NULL),
    {
      suppressWarnings({
        engine$handle(genui_call("card_row", list(title = "Row")))
        engine$handle(genui_call(
          "value_box",
          list(title = "A", column = "mpg", parent_id = "c1")
        ))
        engine$handle(genui_call("scatter_plot", list(x = "mpg", y = "hp")))
        engine$handle(genui_call(
          "update_component",
          list(id = "c3", args = list(color = "wt"))
        ))
        engine$handle(genui_call("remove_component", list(id = "c2")))
      })
      saved$trace <- engine$registry$trace()
      saved$instances <- engine$registry$snapshot()$instances
    }
  )

  # Session two: fresh, no chat anywhere.
  shiny::testServer(
    function(input, output, session) {
      saved$handles <- suppressWarnings(
        genui_replay(saved$trace, catalog, target = "mirror")
      )
    },
    {
      instances <- shiny::isolate(saved$handles$instances())
      expect_identical(instances, saved$instances)
      expect_identical(names(instances), c("c1", "c3"))
      expect_identical(instances$c3$args$color, "wt")
      # replayed canvas is also findable through genui_trace
      expect_length(genui_trace(session, id = "mirror")(), 5)
    }
  )
})

test_that("replay skips entries that no longer validate, with a warning", {
  catalog <- test_catalog()
  trace <- list(
    list(op = "create", id = "c1", component = "value_box", args = list(title = "A", column = "mpg")),
    list(op = "create", id = "c2", component = "retired_widget", args = list()),
    list(op = "create", id = "c3", component = "scatter_plot", args = list(x = "mpg", y = "hp"))
  )
  saved <- new.env(parent = emptyenv())
  shiny::testServer(
    function(input, output, session) {
      warnings <- character()
      saved$handles <- withCallingHandlers(
        genui_replay(trace, catalog, target = "mirror"),
        warning = function(w) {
          warnings <<- c(warnings, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      )
      saved$warnings <- warnings
    },
    {
      expect_true(any(grepl("retired_widget", saved$warnings)))
      instances <- shiny::isolate(saved$handles$instances())
      expect_identical(names(instances), c("c1", "c2"))
      expect_identical(instances$c2$component, "scatter_plot")
    }
  )
})

test_that("malformed traces are rejected", {
  expect_error(
    shinygenui:::trace_entry_call(list(id = "c1")),
    class = "genui_error"
  )
  expect_error(
    shinygenui:::trace_entry_call(list(op = "teleport", id = "c1")),
    class = "genui_error"
  )
})
