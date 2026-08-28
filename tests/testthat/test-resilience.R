# M3: the error feedback loop and session resilience. ellmer wraps tool
# invocation in tryCatch(error = ...) and sends conditionMessage() back to
# the model, so these tests assert on exactly that surface.

engine_module <- function(id, catalog, data = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    engine <- shinygenui:::GenuiEngine$new(catalog, session = session, data = data)
    engine
  })
}

test_that("the model-facing error text carries recovery guidance", {
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = test_catalog(), data = function() NULL),
    {
      # mimic ellmer's invoke_tool() contract
      result <- tryCatch(
        engine$handle(genui_call("value_box", list(title = "A", column = "cylinders"))),
        error = function(e) e
      )
      message <- conditionMessage(result)
      expect_match(message, "cylinders")
      expect_match(message, "mpg")

      result <- tryCatch(
        engine$handle(genui_call("update_component", list(id = "c9", args = "{}"))),
        error = function(e) e
      )
      expect_match(conditionMessage(result), "empty")
    }
  )
})

test_that("a failing ui function leaves creates untouched and updates intact", {
  fragile <- genui_component(
    name = "fragile_card",
    description = "Renders only when text is not 'boom'.",
    args = list(text = "The text."),
    ui = function(id, args) {
      if (identical(args$text, "boom")) {
        stop("cannot render this text")
      }
      NULL
    }
  )
  catalog <- genui_catalog(fragile)
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = catalog, data = function() NULL),
    {
      # failed create: nothing on the canvas, nothing in the trace
      expect_error(
        engine$handle(genui_call("fragile_card", list(text = "boom"))),
        "cannot render"
      )
      expect_identical(engine$registry$size(), 0L)
      expect_length(engine$registry$trace(), 0)

      # failed update: the existing instance keeps its args and stays live
      suppressWarnings(
        engine$handle(genui_call("fragile_card", list(text = "fine")))
      )
      expect_error(
        engine$handle(genui_call(
          "update_component",
          list(id = "c1", args = list(text = "boom"))
        )),
        "cannot render"
      )
      expect_identical(engine$registry$get("c1")$args$text, "fine")
      expect_length(engine$registry$trace(), 1)

      # and the session keeps working afterwards
      suppressWarnings(
        engine$handle(genui_call(
          "update_component",
          list(id = "c1", args = list(text = "better"))
        ))
      )
      expect_identical(engine$registry$get("c1")$args$text, "better")
    }
  )
})

test_that("failures are always logged; successes only when verbose", {
  skip_if_not_installed("withr")

  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = test_catalog(), data = function() NULL),
    {
      expect_message(
        expect_error(
          engine$handle(genui_call("value_box", list(title = "A", column = "nope"))),
          class = "genui_dispatch_error"
        ),
        "value_box call failed"
      )

      # quiet by default on success
      expect_no_message(
        suppressWarnings(
          engine$handle(genui_call("value_box", list(title = "A", column = "mpg")))
        )
      )

      withr::local_options(shinygenui.verbose = TRUE)
      expect_message(
        suppressWarnings(
          engine$handle(genui_call(
            "update_component",
            list(id = "c1", args = list(title = "B"))
          ))
        ),
        "update c1"
      )
    }
  )
})

test_that("check hook failures identify the component and reason", {
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = test_catalog(), data = function() NULL),
    {
      result <- tryCatch(
        engine$handle(genui_call("scatter_plot", list(x = "mpg", y = "mpg"))),
        error = function(e) e
      )
      message <- conditionMessage(result)
      expect_match(message, "scatter_plot")
      expect_match(message, "different columns")
    }
  )
})
