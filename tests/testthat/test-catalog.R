test_that("genui_catalog collects components by name", {
  catalog <- test_catalog()
  expect_s3_class(catalog, "genui_catalog")
  expect_named(
    catalog,
    c("value_box", "scatter_plot", "data_table", "card_row")
  )
  expect_identical(catalog[["value_box"]]$name, "value_box")
  expect_identical(catalog_get(catalog, "scatter_plot")$name, "scatter_plot")
  expect_null(catalog_get(catalog, "nope"))
})

test_that("genui_catalog flattens lists of components", {
  note <- genui_component("note_card", "A note.", ui = function(id, args) NULL)
  pack <- list(
    genui_component("a_card", "A.", ui = function(id, args) NULL),
    genui_component("b_card", "B.", ui = function(id, args) NULL)
  )
  catalog <- genui_catalog(pack, note)
  expect_named(catalog, c("a_card", "b_card", "note_card"))
})

test_that("duplicate component names are rejected", {
  note <- genui_component("note_card", "A note.", ui = function(id, args) NULL)
  expect_error(genui_catalog(note, note), "duplicated", class = "genui_error")
})

test_that("invalid and empty catalogs are rejected", {
  expect_error(genui_catalog(), class = "genui_error")
  expect_error(genui_catalog("nope"), class = "genui_error")
  expect_error(genui_catalog(list("nope")), class = "genui_error")
})

test_that("catalog_has_containers detects container components", {
  expect_true(catalog_has_containers(test_catalog()))
  flat <- genui_catalog(
    genui_component("note_card", "A note.", ui = function(id, args) NULL)
  )
  expect_false(catalog_has_containers(flat))
})

test_that("print method runs", {
  expect_no_error(invisible(capture.output(print(test_catalog()))))
})
