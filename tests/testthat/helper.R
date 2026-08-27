# Internal objects exercised directly by the unit tests.
GenuiRegistry <- shinygenui:::GenuiRegistry
catalog_has_containers <- shinygenui:::catalog_has_containers
catalog_get <- shinygenui:::catalog_get
collect_observers <- shinygenui:::collect_observers

# A small catalog exercising enums, optional args, check hooks, and a
# container. Mirrors the shape of the starter pack without any UI packages.
test_catalog <- function() {
  genui_catalog(
    genui_component(
      name = "value_box",
      description = "A value box summarizing one column.",
      args = list(
        title = ellmer::type_string("Box title."),
        column = ellmer::type_enum(c("mpg", "hp", "wt"), "Column to summarize."),
        digits = ellmer::type_integer("Rounding digits.", required = FALSE)
      ),
      ui = function(id, args) NULL
    ),
    genui_component(
      name = "scatter_plot",
      description = "A scatter plot of two numeric columns.",
      args = list(
        x = ellmer::type_enum(c("mpg", "hp", "wt"), "X column."),
        y = ellmer::type_enum(c("mpg", "hp", "wt"), "Y column."),
        color = ellmer::type_enum(c("mpg", "hp", "wt", "none"), "Color column.", required = FALSE)
      ),
      ui = function(id, args) NULL,
      check = function(args, data) {
        if (identical(args$x, args$y)) "x and y must be different columns." else NULL
      }
    ),
    genui_component(
      name = "data_table",
      description = "A table of selected columns.",
      args = list(
        columns = ellmer::type_array(
          ellmer::type_enum(c("mpg", "hp", "wt"), "A column."),
          "Columns to show."
        ),
        page_size = ellmer::type_integer("Rows per page.", required = FALSE)
      ),
      ui = function(id, args) NULL,
      check = function(args, data) {
        if (!is.null(data) && !all(unlist(args$columns) %in% names(data))) {
          "some requested columns are not in the data."
        }
      }
    ),
    genui_component(
      name = "card_row",
      description = "A horizontal row holding child components.",
      args = list(title = ellmer::type_string("Row title.", required = FALSE)),
      ui = function(id, args) NULL,
      container = TRUE
    )
  )
}

empty_state <- function() {
  list(instances = list(), next_id = 1L)
}

# Applies a call end to end against a registry, like the executor does,
# minus the DOM work.
apply_call <- function(registry, catalog, tool, args = list(), data = NULL) {
  plan <- genui_dispatch(catalog, genui_call(tool, args), registry, data = data)
  registry$apply(plan)
  plan
}

# An observer stand-in: an environment with a destroy() method that flips a
# flag, like shiny::observe() handles.
fake_observer <- function() {
  observer <- new.env(parent = emptyenv())
  observer$destroyed <- FALSE
  observer$destroy <- function() {
    assign("destroyed", TRUE, envir = observer)
  }
  observer
}
