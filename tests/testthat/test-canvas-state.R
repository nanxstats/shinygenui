engine_module <- function(id, catalog, data = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    engine <- shinygenui:::GenuiEngine$new(catalog, session = session, data = data)
    engine
  })
}

test_that("get_canvas_state reports instances and embedded input values", {
  slider_component <- genui_component(
    name = "tuner",
    description = "A slider the user can tune.",
    args = list(label = "Label."),
    ui = function(id, args) {
      ns <- shiny::NS(id)
      shiny::sliderInput(ns("level"), args$label, min = 0, max = 10, value = 5)
    }
  )
  catalog <- genui_catalog(slider_component)
  shiny::testServer(
    engine_module,
    args = list(id = "genui", catalog = catalog, data = function() NULL),
    {
      result <- engine$canvas_state()
      expect_identical(attr(result, "value"), "The canvas is empty.")

      suppressWarnings(
        engine$handle(genui_call("tuner", list(label = "Level")))
      )
      # the user drags the embedded slider; no tool traffic involved
      session$setInputs(`c1-level` = 8L)

      state <- jsonlite::fromJSON(
        attr(engine$canvas_state(), "value"),
        simplifyVector = FALSE
      )
      expect_length(state, 1)
      expect_identical(state[[1]]$id, "c1")
      expect_identical(state[[1]]$component, "tuner")
      expect_identical(state[[1]]$args$label, "Level")
      expect_identical(state[[1]]$inputs$level, 8L)

      # reads are not part of the spec of record
      expect_length(engine$registry$trace(), 1)
    }
  )
})
