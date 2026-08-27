test_that("apply(create) records the instance and advances the counter", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))

  expect_identical(registry$ids(), "c1")
  expect_true(registry$has("c1"))
  expect_identical(registry$size(), 1L)
  instance <- registry$get("c1")
  expect_identical(instance$component, "value_box")
  expect_identical(instance$args, list(title = "A", column = "mpg"))
  expect_identical(registry$snapshot()$next_id, 2L)
})

test_that("ids are never reused after removal", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))
  apply_call(registry, catalog, "remove_component", list(id = "c1"))
  plan <- apply_call(registry, catalog, "value_box", list(title = "B", column = "hp"))
  expect_identical(plan$id, "c2")
  expect_identical(registry$ids(), "c2")
})

test_that("the trace records every validated call in order", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))
  apply_call(registry, catalog, "update_component", list(id = "c2", args = list(color = "wt")))
  apply_call(registry, catalog, "remove_component", list(id = "c1"))
  apply_call(registry, catalog, "clear_canvas")

  trace <- registry$trace()
  expect_length(trace, 5)
  expect_identical(
    vapply(trace, function(x) x$op, character(1)),
    c("create", "create", "update", "remove", "clear")
  )
  expect_identical(trace[[1]]$component, "value_box")
  expect_identical(trace[[1]]$id, "c1")
  # update entries record the validated delta, not the merged args
  expect_identical(trace[[3]]$args, list(color = "wt"))
  expect_identical(trace[[4]]$id, "c1")
})

test_that("replaying a trace through dispatch reproduces the state", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "card_row", list(title = "Row"))
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg", parent_id = "c1"))
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))
  apply_call(registry, catalog, "update_component", list(id = "c3", args = list(color = "wt")))
  apply_call(registry, catalog, "remove_component", list(id = "c2"))

  # Fold the trace into a fresh registry using the same pure pipeline.
  replayed <- GenuiRegistry$new()
  for (entry in registry$trace()) {
    call <- switch(entry$op,
      create = genui_call(
        entry$component,
        c(entry$args, if (!is.null(entry$parent_id)) list(parent_id = entry$parent_id))
      ),
      update = genui_call("update_component", list(id = entry$id, args = entry$args)),
      remove = genui_call("remove_component", list(id = entry$id)),
      clear = genui_call("clear_canvas")
    )
    replayed$apply(genui_dispatch(catalog, call, replayed))
  }

  expect_identical(replayed$snapshot(), registry$snapshot())
})

test_that("set_handles collects observers and update destroys them", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))

  observer1 <- fake_observer()
  observer2 <- fake_observer()
  registry$set_handles("c1", list(observer1, nested = list(observer2), value = 42))
  expect_length(registry$get("c1")$observers, 2)

  apply_call(registry, catalog, "update_component", list(id = "c1", args = list(color = "wt")))
  expect_true(observer1$destroyed)
  expect_true(observer2$destroyed)
  expect_length(registry$get("c1")$observers, 0)
  expect_identical(registry$get("c1")$args$color, "wt")
})

test_that("remove destroys observers of the instance and its descendants", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "card_row", list())
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg", parent_id = "c1"))

  parent_observer <- fake_observer()
  child_observer <- fake_observer()
  registry$set_handles("c1", parent_observer)
  registry$set_handles("c2", child_observer)

  apply_call(registry, catalog, "remove_component", list(id = "c1"))
  expect_true(parent_observer$destroyed)
  expect_true(child_observer$destroyed)
  expect_identical(registry$size(), 0L)
})

test_that("clear destroys all observers and empties the registry", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))
  apply_call(registry, catalog, "value_box", list(title = "B", column = "hp"))
  observer <- fake_observer()
  registry$set_handles("c2", observer)

  apply_call(registry, catalog, "clear_canvas")
  expect_true(observer$destroyed)
  expect_identical(registry$size(), 0L)
  expect_identical(registry$ids(), character())
  # counter still advances
  plan <- apply_call(registry, catalog, "value_box", list(title = "C", column = "wt"))
  expect_identical(plan$id, "c3")
})

test_that("a reactives element is stored as the public hook", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))

  filtered <- function() "the filtered data"
  registry$set_handles("c1", list(reactives = list(filtered = filtered)))
  expect_identical(registry$reactives("c1")$filtered(), "the filtered data")
})

test_that("collect_observers walks plain lists only", {
  observer <- fake_observer()
  classed <- structure(list(observer), class = "some_widget")
  found <- collect_observers(list(a = observer, b = classed, c = "x"))
  expect_length(found, 1)
  expect_length(collect_observers(NULL), 0)
  expect_length(collect_observers("x"), 0)
})

test_that("on_change fires after every applied plan", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  changes <- 0L
  registry$set_on_change(function() changes <<- changes + 1L)

  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))
  apply_call(registry, catalog, "update_component", list(id = "c1", args = list(title = "B")))
  apply_call(registry, catalog, "remove_component", list(id = "c1"))
  expect_identical(changes, 3L)
})

test_that("registry guards against invalid plans and unknown ids", {
  registry <- GenuiRegistry$new()
  expect_error(registry$apply(list(action = "create")), class = "genui_error")
  expect_error(registry$get("c1"), class = "genui_error")
  expect_error(registry$set_handles("c1", NULL), class = "genui_error")
  # destroy_handles on a missing id is a silent no-op (teardown paths race)
  expect_no_error(registry$destroy_handles("c1"))
})
