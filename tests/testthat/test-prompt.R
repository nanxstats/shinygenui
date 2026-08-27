test_that("genui_prompt lists components, args, and enum values", {
  prompt <- genui_prompt(test_catalog())
  expect_match(prompt, "### value_box")
  expect_match(prompt, "A value box summarizing one column.", fixed = TRUE)
  expect_match(prompt, "one of: mpg, hp, wt", fixed = TRUE)
  expect_match(prompt, "`digits` (integer; optional)", fixed = TRUE)
  expect_match(prompt, "array of one of: mpg, hp, wt", fixed = TRUE)
  # container marker and layout section
  expect_match(prompt, "### card_row (container)", fixed = TRUE)
  expect_match(prompt, "parent_id", fixed = TRUE)
  # core behavioral instructions
  expect_match(prompt, "update_component", fixed = TRUE)
  expect_match(prompt, "canvas")
})

test_that("context is included only when provided", {
  with_context <- genui_prompt(test_catalog(), context = "The data is mtcars.")
  expect_match(with_context, "## App context", fixed = TRUE)
  expect_match(with_context, "The data is mtcars.", fixed = TRUE)

  without_context <- genui_prompt(test_catalog())
  expect_no_match(without_context, "## App context", fixed = TRUE)
})

test_that("catalogs without containers omit the layout section", {
  flat <- genui_catalog(
    genui_component("note_card", "A note.", args = list(text = "Text."), ui = function(id, args) NULL)
  )
  prompt <- genui_prompt(flat)
  expect_no_match(prompt, "## Layout", fixed = TRUE)
  expect_no_match(prompt, "parent_id", fixed = TRUE)
})

test_that("a custom template string is rendered with the same data", {
  prompt <- genui_prompt(
    test_catalog(),
    context = "CTX",
    template = "start\n{{#components}}{{name}};{{/components}}{{context}}"
  )
  expect_identical(
    prompt,
    "start\nvalue_box;scatter_plot;data_table;card_row;CTX"
  )
})

test_that("invalid inputs are rejected", {
  expect_error(genui_prompt(list()), class = "genui_error")
  expect_error(
    genui_prompt(test_catalog(), context = 42),
    class = "genui_error"
  )
  expect_error(
    genui_prompt(test_catalog(), template = 42),
    class = "genui_error"
  )
})
