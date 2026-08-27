# Engine tests run under shiny::testServer with a MockShinySession, whose
# sendInsertUI/sendRemoveUI are warning no-ops; suppressWarnings() around
# engine calls silences exactly those.

engine_module <- function(id, catalog, data = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    engine <- shinygenui:::GenuiEngine$new(catalog, session = session, data = data)
    engine
  })
}

# A component whose server creates a real observer and exposes the public
# reactives hook, to prove handle capture works with live Shiny objects.
counter_component <- function() {
  genui_component(
    name = "counter",
    description = "A button counting its own clicks.",
    args = list(label = "Button label."),
    ui = function(id, args) {
      ns <- shiny::NS(id)
      shiny::actionButton(ns("btn"), args$label)
    },
    server = function(id, args, data) {
      shiny::moduleServer(id, function(input, output, session) {
        clicks <- shiny::reactiveVal(0L)
        observer <- shiny::observeEvent(input$btn, {
          clicks(clicks() + 1L)
        })
        list(observer, reactives = list(clicks = clicks))
      })
    }
  )
}

test_that("engine handles create calls end to end", {
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = test_catalog(), data = function() NULL),
    {
      result <- suppressWarnings(
        engine$handle(genui_call("value_box", list(title = "A", column = "mpg")))
      )
      expect_true(inherits(result, "ellmer::ContentToolResult"))
      expect_match(attr(result, "value"), "c1")
      expect_match(attr(result, "value"), "value_box")
      expect_identical(engine$registry$ids(), "c1")
      expect_length(engine$registry$trace(), 1)
    }
  )
})

test_that("engine instantiates component servers and captures handles", {
  catalog <- genui_catalog(counter_component())
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = catalog, data = function() NULL),
    {
      suppressWarnings(
        engine$handle(genui_call("counter", list(label = "Click me")))
      )
      instance <- engine$registry$get("c1")
      expect_length(instance$observers, 1)
      expect_true(inherits(instance$observers[[1]], "Observer"))
      expect_identical(engine$registry$reactives("c1")$clicks(), 0L)
    }
  )
})

test_that("engine updates re-instantiate and removes tear down", {
  catalog <- genui_catalog(counter_component())
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = catalog, data = function() NULL),
    {
      suppressWarnings(
        engine$handle(genui_call("counter", list(label = "One")))
      )
      first_observer <- engine$registry$get("c1")$observers[[1]]

      result <- suppressWarnings(
        engine$handle(genui_call(
          "update_component",
          list(id = "c1", args = list(label = "Two"))
        ))
      )
      expect_match(attr(result, "value"), "Updated")
      expect_identical(engine$registry$get("c1")$args$label, "Two")
      # a fresh observer was captured for the re-instantiated module
      second_observer <- engine$registry$get("c1")$observers[[1]]
      expect_false(identical(first_observer, second_observer))

      result <- suppressWarnings(
        engine$handle(genui_call("remove_component", list(id = "c1")))
      )
      expect_match(attr(result, "value"), "Removed")
      expect_identical(engine$registry$size(), 0L)
    }
  )
})

test_that("dispatch errors from handle leave no partial state", {
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = test_catalog(), data = function() NULL),
    {
      expect_error(
        engine$handle(genui_call("value_box", list(title = "A", column = "nope"))),
        class = "genui_dispatch_error"
      )
      expect_identical(engine$registry$size(), 0L)
      expect_length(engine$registry$trace(), 0)
    }
  )
})

test_that("a failing component server rolls the create back", {
  broken <- genui_component(
    name = "broken_card",
    description = "Always fails to wire.",
    args = list(text = "Text."),
    ui = function(id, args) NULL,
    server = function(id, args, data) stop("wiring exploded")
  )
  catalog <- genui_catalog(broken)
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = catalog, data = function() NULL),
    {
      expect_error(
        suppressWarnings(
          engine$handle(genui_call("broken_card", list(text = "x")))
        ),
        "wiring exploded"
      )
      expect_identical(engine$registry$size(), 0L)
      expect_length(engine$registry$trace(), 0)
    }
  )
})

test_that("check hooks see the current data value", {
  shiny::testServer(
    engine_module,
    args = list(
      id = "genui",
      catalog = test_catalog(),
      data = function() data.frame(mpg = 1, hp = 2)
    ),
    {
      # wt passes the enum but fails the data_table check hook on live data
      expect_error(
        engine$handle(genui_call("data_table", list(columns = "wt"))),
        class = "genui_dispatch_error"
      )
      suppressWarnings(
        engine$handle(genui_call("data_table", list(columns = "mpg")))
      )
      expect_identical(engine$registry$ids(), "c1")
    }
  )
})
