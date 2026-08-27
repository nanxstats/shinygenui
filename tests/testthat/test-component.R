test_that("genui_component builds a component with defaults", {
  component <- genui_component(
    name = "note_card",
    description = "A note.",
    args = list(text = ellmer::type_string("The text.")),
    ui = function(id, args) NULL
  )
  expect_s3_class(component, "genui_component")
  expect_identical(component$name, "note_card")
  expect_null(component$server)
  expect_null(component$check)
  expect_false(component$container)
  expect_identical(component$width, "auto")
})

test_that("plain strings in args are promoted to type_string", {
  component <- genui_component(
    name = "note_card",
    description = "A note.",
    args = list(text = "The text to show."),
    ui = function(id, args) NULL
  )
  expect_true(inherits(component$args$text, "ellmer::Type"))
  expect_identical(attr(component$args$text, "type", exact = TRUE), "string")
  expect_identical(
    attr(component$args$text, "description", exact = TRUE),
    "The text to show."
  )
})

test_that("component names are validated", {
  ui <- function(id, args) NULL
  expect_error(
    genui_component("BadName", "d", ui = ui),
    class = "genui_error"
  )
  expect_error(
    genui_component("bad name", "d", ui = ui),
    class = "genui_error"
  )
  expect_error(
    genui_component("1bad", "d", ui = ui),
    class = "genui_error"
  )
  expect_error(
    genui_component("update_component", "d", ui = ui),
    "reserved",
    class = "genui_error"
  )
})

test_that("description must be a non-empty string", {
  ui <- function(id, args) NULL
  expect_error(genui_component("x_card", "", ui = ui), class = "genui_error")
  expect_error(genui_component("x_card", "  ", ui = ui), class = "genui_error")
  expect_error(genui_component("x_card", NULL, ui = ui), class = "genui_error")
})

test_that("args must be a uniquely named list of ellmer types", {
  ui <- function(id, args) NULL
  expect_error(
    genui_component("x_card", "d", args = list(ellmer::type_string()), ui = ui),
    class = "genui_error"
  )
  expect_error(
    genui_component("x_card", "d", args = list(a = 5), ui = ui),
    class = "genui_error"
  )
  expect_error(
    genui_component(
      "x_card",
      "d",
      args = list(a = ellmer::type_string(), a = ellmer::type_string()),
      ui = ui
    ),
    class = "genui_error"
  )
  expect_error(
    genui_component("x_card", "d", args = list(`bad name` = "x"), ui = ui),
    class = "genui_error"
  )
})

test_that("reserved argument names are rejected", {
  ui <- function(id, args) NULL
  expect_error(
    genui_component("x_card", "d", args = list(id = "The id."), ui = ui),
    "reserved",
    class = "genui_error"
  )
  expect_error(
    genui_component("x_card", "d", args = list(parent_id = "The parent."), ui = ui),
    "reserved",
    class = "genui_error"
  )
})

test_that("ui, server, and check arities are validated", {
  expect_error(
    genui_component("x_card", "d", ui = "not a function"),
    class = "genui_error"
  )
  expect_error(
    genui_component("x_card", "d", ui = function(id) NULL),
    class = "genui_error"
  )
  expect_error(
    genui_component(
      "x_card",
      "d",
      ui = function(id, args) NULL,
      server = function(id) NULL
    ),
    class = "genui_error"
  )
  expect_error(
    genui_component(
      "x_card",
      "d",
      ui = function(id, args) NULL,
      check = function(args) NULL
    ),
    class = "genui_error"
  )
  # Dots satisfy any arity.
  expect_no_error(
    genui_component(
      "x_card",
      "d",
      ui = function(...) NULL,
      server = function(id, ...) NULL
    )
  )
})

test_that("container and width are validated", {
  ui <- function(id, args) NULL
  expect_error(
    genui_component("x_card", "d", ui = ui, container = "yes"),
    class = "genui_error"
  )
  expect_error(genui_component("x_card", "d", ui = ui, width = "huge"))
  component <- genui_component("x_card", "d", ui = ui, width = "full")
  expect_identical(component$width, "full")
})

test_that("print method runs", {
  component <- genui_component(
    name = "note_card",
    description = "A note.",
    args = list(text = "The text."),
    ui = function(id, args) NULL,
    container = TRUE
  )
  expect_no_error(invisible(capture.output(print(component))))
})
