# All tests drive genui_dispatch() with hand-built genui_call objects:
# no Shiny session, no network, no LLM.

test_that("create plans assign sequential ids and validated args", {
  catalog <- test_catalog()
  plan <- genui_dispatch(
    catalog,
    genui_call("value_box", list(title = "Average MPG", column = "mpg")),
    empty_state()
  )
  expect_s3_class(plan, "genui_plan")
  expect_identical(plan$action, "create")
  expect_identical(plan$id, "c1")
  expect_identical(plan$component, "value_box")
  expect_identical(plan$args, list(title = "Average MPG", column = "mpg"))
  expect_null(plan$parent_id)
})

test_that("ids advance with registry state", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  plan1 <- apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))
  plan2 <- apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))
  expect_identical(plan1$id, "c1")
  expect_identical(plan2$id, "c2")
})

test_that("plain-list states derive next_id from existing ids", {
  catalog <- test_catalog()
  state <- list(
    instances = list(
      c5 = list(component = "value_box", args = list(title = "A", column = "mpg"), parent_id = NULL)
    )
  )
  plan <- genui_dispatch(
    catalog,
    genui_call("value_box", list(title = "B", column = "hp")),
    state
  )
  expect_identical(plan$id, "c6")
})

test_that("unknown components are rejected with the available names", {
  err <- expect_error(
    genui_dispatch(test_catalog(), genui_call("pie_chart"), empty_state()),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "pie_chart")
  expect_match(conditionMessage(err), "scatter_plot")
})

test_that("unknown arguments are rejected with the declared names", {
  err <- expect_error(
    genui_dispatch(
      test_catalog(),
      genui_call("value_box", list(title = "A", column = "mpg", style = "big")),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "style")
  expect_match(conditionMessage(err), "digits")
})

test_that("missing required arguments are rejected", {
  err <- expect_error(
    genui_dispatch(
      test_catalog(),
      genui_call("value_box", list(title = "A")),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "column")
})

test_that("hallucinated enum values are rejected with the allowed set", {
  err <- expect_error(
    genui_dispatch(
      test_catalog(),
      genui_call("value_box", list(title = "A", column = "cylinders")),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "cylinders")
  expect_match(conditionMessage(err), "mpg")
})

test_that("basic types are enforced", {
  catalog <- test_catalog()
  state <- empty_state()
  # title must be a string
  expect_error(
    genui_dispatch(
      catalog,
      genui_call("value_box", list(title = 42, column = "mpg")),
      state
    ),
    class = "genui_dispatch_error"
  )
  # digits must be a whole number
  expect_error(
    genui_dispatch(
      catalog,
      genui_call("value_box", list(title = "A", column = "mpg", digits = 1.5)),
      state
    ),
    class = "genui_dispatch_error"
  )
  # whole doubles and true integers both pass
  expect_no_error(
    genui_dispatch(
      catalog,
      genui_call("value_box", list(title = "A", column = "mpg", digits = 2)),
      state
    )
  )
  expect_no_error(
    genui_dispatch(
      catalog,
      genui_call("value_box", list(title = "A", column = "mpg", digits = 2L)),
      state
    )
  )
})

test_that("array arguments validate each element", {
  catalog <- test_catalog()
  plan <- genui_dispatch(
    catalog,
    genui_call("data_table", list(columns = c("mpg", "hp"))),
    empty_state()
  )
  expect_identical(plan$args$columns, c("mpg", "hp"))

  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call("data_table", list(columns = c("mpg", "gears"))),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "gears")

  # named lists are not arrays
  expect_error(
    genui_dispatch(
      catalog,
      genui_call("data_table", list(columns = list(a = "mpg"))),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
})

test_that("arguments parsed from JSON come back in canonical form", {
  catalog <- test_catalog()
  plan <- genui_dispatch(
    catalog,
    genui_call(
      "data_table",
      json_args('{"columns": ["mpg", "hp"], "page_size": 5}')
    ),
    empty_state()
  )
  # an array of scalars is an atomic vector, however it was spelled
  expect_identical(plan$args$columns, c("mpg", "hp"))
  expect_identical(plan$args$page_size, 5L)

  # an empty array stays an array instead of becoming absent
  plan <- genui_dispatch(
    catalog,
    genui_call("data_table", json_args('{"columns": []}')),
    empty_state()
  )
  expect_identical(plan$args$columns, character())

  # a scalar wrapped in a one-element array is unwrapped
  plan <- genui_dispatch(
    catalog,
    genui_call("value_box", json_args('{"title": ["A"], "column": ["mpg"]}')),
    empty_state()
  )
  expect_identical(plan$args, list(title = "A", column = "mpg"))

  # canonical arguments validate to themselves, so replay is stable
  again <- genui_dispatch(
    catalog,
    genui_call("value_box", plan$args),
    empty_state()
  )
  expect_identical(again$args, plan$args)
})

test_that("arrays of objects and objects keep their structure", {
  catalog <- structured_catalog()
  plan <- genui_dispatch(
    catalog,
    genui_call(
      "checklist",
      json_args(
        '{
          "items": [{"label": "a", "done": true}, {"label": "b", "done": null}],
          "style": {"color": "red", "size": null},
          "scores": [1, 2.5]
        }'
      )
    ),
    empty_state()
  )
  # null fields are absent fields, like null arguments
  expect_identical(
    plan$args,
    list(
      items = list(list(label = "a", done = TRUE), list(label = "b")),
      style = list(color = "red"),
      scores = c(1, 2.5)
    )
  )

  again <- genui_dispatch(
    catalog,
    genui_call("checklist", plan$args),
    empty_state()
  )
  expect_identical(again$args, plan$args)
})

test_that("structured arguments are validated field by field", {
  catalog <- structured_catalog()
  bad <- function(json) {
    expect_error(
      genui_dispatch(
        catalog,
        genui_call("checklist", json_args(json)),
        empty_state()
      ),
      class = "genui_dispatch_error"
    )
  }

  err <- bad('{"items": [{"done": true}]}')
  expect_match(conditionMessage(err), "label")

  err <- bad('{"items": [{"label": "a", "note": "x"}]}')
  expect_match(conditionMessage(err), "note")

  err <- bad('{"items": [{"label": "a"}], "style": {"color": "green"}}')
  expect_match(conditionMessage(err), "green")
  expect_match(conditionMessage(err), "blue")

  # an object where an array is expected
  bad('{"items": {"label": "a"}}')
})

test_that("rejected values are quoted back as the model wrote them", {
  catalog <- structured_catalog()
  message_for <- function(json) {
    conditionMessage(expect_error(
      genui_dispatch(
        catalog,
        genui_call("checklist", json_args(json)),
        empty_state()
      ),
      class = "genui_dispatch_error"
    ))
  }

  expect_match(
    message_for('{"items": [{"label": ["a", "b"]}]}'),
    'not ["a","b"]',
    fixed = TRUE
  )
  expect_match(
    message_for('{"items": [{"label": "a"}], "scores": [1, null]}'),
    "not null",
    fixed = TRUE
  )
  # braces in a model-supplied value are text, not cli markup
  expect_match(
    message_for('{"items": [{"label": "a"}], "style": {"color": "{.val x}"}}'),
    'Invalid value "{.val x}"',
    fixed = TRUE
  )
})

test_that("NULL optional arguments are treated as absent", {
  plan <- genui_dispatch(
    test_catalog(),
    genui_call("value_box", list(title = "A", column = "mpg", digits = NULL)),
    empty_state()
  )
  expect_named(plan$args, c("title", "column"))
})

test_that("check hooks reject semantically invalid args", {
  err <- expect_error(
    genui_dispatch(
      test_catalog(),
      genui_call("scatter_plot", list(x = "mpg", y = "mpg")),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "different columns")
})

test_that("check hooks receive the data value", {
  catalog <- test_catalog()
  data <- data.frame(mpg = 1, hp = 2)
  # wt is in the enum but not in this data frame
  expect_error(
    genui_dispatch(
      catalog,
      genui_call("data_table", list(columns = "wt")),
      empty_state(),
      data = data
    ),
    class = "genui_dispatch_error"
  )
  expect_no_error(
    genui_dispatch(
      catalog,
      genui_call("data_table", list(columns = "mpg")),
      empty_state(),
      data = data
    )
  )
})

# Containers ---------------------------------------------------------------

test_that("create can target a container parent", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  row <- apply_call(registry, catalog, "card_row", list(title = "Row"))
  plan <- genui_dispatch(
    catalog,
    genui_call("value_box", list(title = "A", column = "mpg", parent_id = row$id)),
    registry
  )
  expect_identical(plan$parent_id, "c1")
  expect_false("parent_id" %in% names(plan$args))
})

test_that("parent_id must reference an existing container", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))

  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call("value_box", list(title = "B", column = "hp", parent_id = "c9")),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "c9")

  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call("value_box", list(title = "B", column = "hp", parent_id = "c1")),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "not a container")
})

# Update -------------------------------------------------------------------

test_that("update merges partial args over current args", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))

  plan <- genui_dispatch(
    catalog,
    genui_call("update_component", list(id = "c1", args = list(color = "wt"))),
    registry
  )
  expect_identical(plan$action, "update")
  expect_identical(plan$id, "c1")
  expect_identical(plan$args, list(x = "mpg", y = "hp", color = "wt"))
  expect_identical(plan$delta, list(color = "wt"))
})

test_that("update accepts args as a JSON object string", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))

  plan <- genui_dispatch(
    catalog,
    genui_call("update_component", list(id = "c1", args = '{"color": "wt"}')),
    registry
  )
  expect_identical(plan$args$color, "wt")

  expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c1", args = "{not json")),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c1", args = '["wt"]')),
      registry
    ),
    class = "genui_dispatch_error"
  )
})

test_that("update returns the same canonical form as create", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "data_table", json_args('{"columns": ["mpg"]}'))

  plan <- genui_dispatch(
    catalog,
    genui_call(
      "update_component",
      list(id = "c1", args = '{"columns": ["hp", "wt"], "page_size": 20}')
    ),
    registry
  )
  expect_identical(plan$args, list(columns = c("hp", "wt"), page_size = 20L))
  # the delta recorded in the trace is canonical too
  expect_identical(plan$delta, list(columns = c("hp", "wt"), page_size = 20L))

  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call(
        "update_component",
        list(id = "c1", args = '{"columns": ["hp", "gears"]}')
      ),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "gears")
})

test_that("update replaces arrays and objects as a whole", {
  catalog <- structured_catalog()
  registry <- GenuiRegistry$new()
  apply_call(
    registry,
    catalog,
    "checklist",
    json_args(
      '{
        "items": [{"label": "a", "done": true}, {"label": "b"}],
        "style": {"color": "red", "size": 12}
      }'
    )
  )

  plan <- genui_dispatch(
    catalog,
    genui_call(
      "update_component",
      list(
        id = "c1",
        args = '{"items": [{"label": "c"}], "style": {"color": "blue"}}'
      )
    ),
    registry
  )
  expect_identical(plan$args$items, list(list(label = "c")))
  # no leftover `size` from the previous object
  expect_identical(plan$args$style, list(color = "blue"))

  # a supplied object must be complete on its own
  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call(
        "update_component",
        list(id = "c1", args = '{"style": {"size": 14}}')
      ),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "color")
})

test_that("built-in tools tolerate scalars wrapped in an array", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "card_row", list())
  apply_call(
    registry,
    catalog,
    "value_box",
    json_args('{"title": "A", "column": "mpg", "parent_id": ["c1"]}')
  )
  expect_identical(registry$get("c2")$parent_id, "c1")

  plan <- genui_dispatch(
    catalog,
    genui_call(
      "update_component",
      json_args('{"id": ["c2"], "args": ["{\\"title\\": \\"B\\"}"]}')
    ),
    registry
  )
  expect_identical(plan$args$title, "B")

  plan <- genui_dispatch(
    catalog,
    genui_call("remove_component", json_args('{"id": ["c2"]}')),
    registry
  )
  expect_identical(plan$id, "c2")
})

test_that("JSON null resets an optional argument to its default", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(
    registry,
    catalog,
    "value_box",
    list(title = "A", column = "mpg", digits = 2)
  )

  plan <- genui_dispatch(
    catalog,
    genui_call("update_component", list(id = "c1", args = '{"digits": null}')),
    registry
  )
  expect_named(plan$args, c("title", "column"))
})

test_that("nulling a required argument is rejected", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg"))

  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c1", args = '{"column": null}')),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "column")
})

test_that("update validates ids, argument names, and enum values", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))

  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c9", args = list(x = "wt"))),
      registry
    ),
    class = "genui_dispatch_error"
  )
  # message lists current instances so the model can recover
  expect_match(conditionMessage(err), "c1")
  expect_match(conditionMessage(err), "scatter_plot")

  expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c1", args = list(bins = 30))),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c1", args = list(x = "gears"))),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c1", args = list(parent_id = "c2"))),
      registry
    ),
    class = "genui_dispatch_error"
  )
})

test_that("update re-runs the check hook on merged args", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))

  err <- expect_error(
    genui_dispatch(
      catalog,
      genui_call("update_component", list(id = "c1", args = list(y = "mpg"))),
      registry
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "different columns")
})

test_that("update with no changes re-renders as-is", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "scatter_plot", list(x = "mpg", y = "hp"))

  plan <- genui_dispatch(
    catalog,
    genui_call("update_component", list(id = "c1")),
    registry
  )
  expect_identical(plan$args, list(x = "mpg", y = "hp"))
  expect_identical(plan$delta, list())
})

# Remove and clear ---------------------------------------------------------

test_that("remove cascades to descendants, leaves first", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "card_row", list()) # c1
  apply_call(registry, catalog, "card_row", list(parent_id = "c1")) # c2
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg", parent_id = "c2")) # c3
  apply_call(registry, catalog, "value_box", list(title = "B", column = "hp", parent_id = "c1")) # c4

  plan <- genui_dispatch(catalog, genui_call("remove_component", list(id = "c1")), registry)
  expect_identical(plan$action, "remove")
  expect_identical(plan$id, "c1")
  expect_identical(plan$ids, c("c3", "c2", "c4", "c1"))
})

test_that("remove validates the id", {
  err <- expect_error(
    genui_dispatch(
      test_catalog(),
      genui_call("remove_component", list(id = "c1")),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
  expect_match(conditionMessage(err), "empty")

  expect_error(
    genui_dispatch(
      test_catalog(),
      genui_call("remove_component", list()),
      empty_state()
    ),
    class = "genui_dispatch_error"
  )
})

test_that("clear plans all instances, leaves first", {
  catalog <- test_catalog()
  registry <- GenuiRegistry$new()
  apply_call(registry, catalog, "value_box", list(title = "A", column = "mpg")) # c1
  apply_call(registry, catalog, "card_row", list()) # c2
  apply_call(registry, catalog, "value_box", list(title = "B", column = "hp", parent_id = "c2")) # c3

  plan <- genui_dispatch(catalog, genui_call("clear_canvas"), registry)
  expect_identical(plan$action, "clear")
  expect_identical(plan$ids, c("c1", "c3", "c2"))
})

test_that("clear on an empty canvas is a valid no-op plan", {
  plan <- genui_dispatch(test_catalog(), genui_call("clear_canvas"), empty_state())
  expect_identical(plan$ids, character())
})

# Call and state coercion --------------------------------------------------

test_that("genui_call validates its inputs", {
  expect_error(genui_call(1), class = "genui_error")
  expect_error(genui_call("x", args = list(1, 2)), class = "genui_error")
  expect_no_error(genui_call("x"))
})

test_that("plain lists are coerced to calls", {
  plan <- genui_dispatch(
    test_catalog(),
    list(tool = "value_box", args = list(title = "A", column = "mpg")),
    empty_state()
  )
  expect_identical(plan$id, "c1")
  expect_error(
    genui_dispatch(test_catalog(), list(args = list()), empty_state()),
    class = "genui_error"
  )
})

test_that("invalid states are rejected", {
  expect_error(
    genui_dispatch(test_catalog(), genui_call("value_box"), "nope"),
    class = "genui_error"
  )
})

test_that("catalog argument is validated", {
  expect_error(
    genui_dispatch(list(), genui_call("value_box"), empty_state()),
    class = "genui_error"
  )
})
