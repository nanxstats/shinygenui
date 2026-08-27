# Tool compilation is tested with a fake engine that records the normalized
# calls it receives; no Shiny session or LLM.

fake_engine <- function() {
  calls <- list()
  env <- new.env(parent = emptyenv())
  env$handle <- function(call) {
    env$calls <- c(env$calls, list(call))
    call
  }
  env$calls <- calls
  env
}

test_that("compile_tools produces one tool per component plus built-ins", {
  tools <- shinygenui:::compile_tools(test_catalog(), fake_engine())
  names <- vapply(tools, function(tool) attr(tool, "name"), character(1))
  expect_identical(
    names,
    c(
      "value_box", "scatter_plot", "data_table", "card_row",
      "update_component", "remove_component", "clear_canvas"
    )
  )
  for (tool in tools) {
    expect_true(inherits(tool, "ellmer::ToolDef"))
  }
})

test_that("compiled tool formals match the declared arguments plus parent_id", {
  engine <- fake_engine()
  tools <- shinygenui:::compile_tools(test_catalog(), engine)
  value_box <- tools[[1]]
  # test_catalog has a container, so parent_id is added everywhere
  expect_identical(
    names(formals(value_box)),
    c("title", "column", "digits", "parent_id")
  )

  flat_catalog <- genui_catalog(
    genui_component("note_card", "A note.", args = list(text = "Text."), ui = function(id, args) NULL)
  )
  flat_tools <- shinygenui:::compile_tools(flat_catalog, engine)
  expect_identical(names(formals(flat_tools[[1]])), "text")
})

test_that("calling a compiled tool forwards a normalized genui_call", {
  engine <- fake_engine()
  tools <- shinygenui:::compile_tools(test_catalog(), engine)
  value_box <- tools[[1]]

  call <- value_box(title = "A", column = "mpg")
  expect_s3_class(call, "genui_call")
  expect_identical(call$tool, "value_box")
  # omitted optional arguments (digits, parent_id) are dropped, not NULL
  expect_identical(call$args, list(title = "A", column = "mpg"))
  expect_length(engine$calls, 1)
})

test_that("built-in tools forward id and args", {
  engine <- fake_engine()
  tools <- shinygenui:::compile_tools(test_catalog(), engine)
  update <- tools[[5]]
  remove <- tools[[6]]
  clear <- tools[[7]]

  call <- update(id = "c1", args = '{"title": "B"}')
  expect_identical(call$tool, "update_component")
  expect_identical(call$args, list(id = "c1", args = '{"title": "B"}'))

  call <- remove(id = "c2")
  expect_identical(call$tool, "remove_component")
  expect_identical(call$args, list(id = "c2"))

  call <- clear()
  expect_identical(call$tool, "clear_canvas")
  expect_identical(call$args, list())
})

test_that("make_tool_fn handles zero-argument components", {
  handler <- function(args) args
  fn <- shinygenui:::make_tool_fn(character(), handler)
  expect_length(formals(fn), 0)
  expect_length(fn(), 0)
})
