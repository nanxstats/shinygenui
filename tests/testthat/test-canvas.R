test_that("genui_canvas renders a namespaced grid container", {
  canvas <- genui_canvas("canvas")
  html <- as.character(canvas)
  expect_match(html, 'id="canvas-canvas"', fixed = TRUE)
  expect_match(html, "genui-canvas", fixed = TRUE)
  expect_match(html, 'data-placeholder="Components will appear here."', fixed = TRUE)
})

test_that("genui_canvas attaches the package stylesheet", {
  deps <- htmltools::findDependencies(genui_canvas("x"))
  names <- vapply(deps, function(dep) dep$name, character(1))
  expect_true("shinygenui" %in% names)
})

test_that("extra attributes and children pass through", {
  canvas <- genui_canvas("x", class = "extra", htmltools::h1("hello"))
  html <- as.character(canvas)
  expect_match(html, "extra", fixed = TRUE)
  expect_match(html, "<h1>hello</h1>", fixed = TRUE)
})
