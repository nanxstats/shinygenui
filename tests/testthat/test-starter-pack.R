skip_if_not_installed("ggplot2")
skip_if_not_installed("DT")

test_that("the pack builds a five-component catalog", {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))
  expect_named(
    catalog,
    c("value_box", "markdown_card", "data_table", "scatter_plot", "histogram")
  )
})

test_that("column arguments are grounded as enums when data is given", {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))
  column_type <- catalog$value_box$args$column
  expect_true(inherits(column_type, "ellmer::TypeEnum"))
  expect_setequal(attr(column_type, "values"), names(mtcars))

  color_type <- catalog$scatter_plot$args$color
  expect_true("none" %in% attr(color_type, "values"))

  # without data, columns fall back to free-form strings
  loose <- genui_catalog(genui_components_bslib())
  expect_identical(attr(loose$value_box$args$column, "type"), "string")
})

test_that("check hooks validate columns against the live data", {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))
  small <- data.frame(mpg = 1:3)

  expect_null(
    catalog$value_box$check(list(column = "mpg", agg = "mean"), small)
  )
  expect_match(
    catalog$value_box$check(list(column = "hp", agg = "mean"), small),
    "does not exist"
  )
  expect_match(
    catalog$histogram$check(list(column = "name"), data.frame(name = "a")),
    "not numeric"
  )
  expect_match(
    catalog$data_table$check(list(columns = c("mpg", "hp")), small),
    "hp"
  )
  expect_null(
    catalog$scatter_plot$check(list(x = "mpg", y = "mpg", color = "none"), small)
  )
})

test_that("component ui functions produce tags", {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))

  box <- catalog$value_box$ui("g-c1", list(title = "T", column = "mpg", agg = "mean"))
  expect_match(as.character(box), "g-c1-value", fixed = TRUE)

  card <- catalog$markdown_card$ui("g-c2", list(title = "Note", text = "**hi**"))
  html <- as.character(card)
  expect_match(html, "Note", fixed = TRUE)
  expect_match(html, "<strong>hi</strong>", fixed = TRUE)

  hist <- catalog$histogram$ui("g-c3", list(column = "hp", bins = 100L))
  html <- as.character(hist)
  expect_match(html, "g-c3-bins", fixed = TRUE)
  # initial bins are clamped into the slider range
  expect_match(html, 'data-max="60"', fixed = TRUE)
  expect_match(html, 'data-from="60"', fixed = TRUE)
})

test_that("starter components render server-side inside the engine", {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))
  shiny::testServer(
    function(id, catalog, data) {
      shiny::moduleServer(id, function(input, output, session) {
        engine <- shinygenui:::GenuiEngine$new(catalog, session = session, data = data)
        engine
      })
    },
    args = list(
      id = "genui",
      catalog = catalog,
      data = function() mtcars
    ),
    {
      suppressWarnings({
        engine$handle(genui_call(
          "scatter_plot",
          list(x = "mpg", y = "hp", color = "cyl")
        ))
        engine$handle(genui_call("histogram", list(column = "hp")))
        engine$handle(genui_call(
          "value_box",
          list(title = "Average MPG", column = "mpg", agg = "mean")
        ))
        engine$handle(genui_call("data_table", list(columns = c("mpg", "hp"))))
      })
      expect_identical(engine$registry$ids(), c("c1", "c2", "c3", "c4"))
      # a hallucinated column is a dispatch error the model can correct
      expect_error(
        engine$handle(genui_call("histogram", list(column = "gears"))),
        class = "genui_dispatch_error"
      )
    }
  )
})

test_that("data must be a data frame when supplied", {
  expect_error(genui_components_bslib(data = "mtcars"), class = "genui_error")
})
