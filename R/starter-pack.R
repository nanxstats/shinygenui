#' Starter component pack built on bslib
#'
#' A small, general-purpose catalog: a value box, a markdown card, a data
#' table, a scatter plot, and a histogram with an embedded bin-count slider
#' (the reference interactive component: dragging the slider re-renders at
#' Shiny speed with no LLM round trip). Pass the result to
#' [genui_catalog()], optionally alongside your own components.
#'
#' When `data` is supplied, column arguments become enums of the actual
#' column names, so a hallucinated column is a schema violation the model
#' must correct. Each component also validates columns against the live
#' data through its `check()` hook at render time.
#'
#' @param data Optional data frame used to ground column arguments as enums
#'   at catalog build time. Typically the same data your [genui_server()]
#'   `data` reactive returns. With `NULL`, column arguments are free-form
#'   strings validated only by the `check()` hooks.
#'
#' @return A list of [genui_component()] objects.
#' @export
#' @examplesIf rlang::is_installed(c("ggplot2", "DT"))
#' catalog <- genui_catalog(genui_components_bslib(data = mtcars))
#' names(catalog)
genui_components_bslib <- function(data = NULL) {
  if (!is.null(data) && !is.data.frame(data)) {
    genui_abort("{.arg data} must be a data frame or `NULL`.")
  }
  rlang::check_installed(
    c("ggplot2", "DT"),
    reason = "to use the shinygenui starter components."
  )

  list(
    component_value_box(data),
    component_markdown_card(),
    component_data_table(data),
    component_scatter_plot(data),
    component_histogram(data)
  )
}

# Column argument grounded as an enum when data is available.
column_arg <- function(
  data,
  description,
  numeric_only = FALSE,
  required = TRUE,
  extra = character()
) {
  if (is.null(data)) {
    return(ellmer::type_string(description, required = required))
  }
  cols <- names(data)
  if (numeric_only) {
    cols <- cols[vapply(data, is.numeric, logical(1))]
  }
  ellmer::type_enum(unique(c(cols, extra)), description, required = required)
}

# Render-time column validation against the live data; complements the
# build-time enum grounding (the data reactive may have drifted since).
check_column <- function(data, column, numeric = FALSE) {
  if (!is.data.frame(data) || is.null(column)) {
    return(NULL)
  }
  if (!column %in% names(data)) {
    return(sprintf(
      "Column \"%s\" does not exist in the current data. Available columns: %s.",
      column,
      paste(names(data), collapse = ", ")
    ))
  }
  if (numeric && !is.numeric(data[[column]])) {
    return(sprintf("Column \"%s\" is not numeric.", column))
  }
  NULL
}

component_value_box <- function(data) {
  genui_component(
    name = "value_box",
    description = paste(
      "A compact box highlighting one summary statistic of a numeric column,",
      "computed from the live data.",
      "Use it for headline numbers such as an average or a count."
    ),
    args = list(
      title = ellmer::type_string(
        "Short label above the value, like \"Average MPG\"."
      ),
      column = column_arg(data, "Column to summarize.", numeric_only = TRUE),
      agg = ellmer::type_enum(
        c("mean", "median", "min", "max", "sum", "count"),
        "Summary statistic to compute."
      ),
      digits = ellmer::type_integer(
        "Decimal places to show (default 2).",
        required = FALSE
      )
    ),
    ui = function(id, args) {
      ns <- shiny::NS(id)
      bslib::value_box(
        title = args$title,
        value = shiny::textOutput(ns("value")),
        theme = "primary"
      )
    },
    server = function(id, args, data) {
      shiny::moduleServer(id, function(input, output, session) {
        output$value <- shiny::renderText({
          df <- data()
          shiny::req(is.data.frame(df))
          column <- df[[args$column]]
          value <- switch(
            args$agg,
            mean = mean(column, na.rm = TRUE),
            median = stats::median(column, na.rm = TRUE),
            min = min(column, na.rm = TRUE),
            max = max(column, na.rm = TRUE),
            sum = sum(column, na.rm = TRUE),
            count = sum(!is.na(column))
          )
          format(
            round(value, args$digits %||% 2L),
            big.mark = ",",
            scientific = FALSE
          )
        })
      })
    },
    check = function(args, data) {
      check_column(data, args$column, numeric = !identical(args$agg, "count"))
    }
  )
}

component_markdown_card <- function() {
  genui_component(
    name = "markdown_card",
    description = paste(
      "A card rendering a short markdown note on the canvas.",
      "Use it for explanations or takeaways that should sit next to the",
      "visuals rather than scroll away in the chat."
    ),
    args = list(
      title = ellmer::type_string("Card header text.", required = FALSE),
      text = ellmer::type_string(
        "Markdown body: a few sentences or a short bullet list."
      )
    ),
    ui = function(id, args) {
      bslib::card(
        if (!is.null(args$title)) bslib::card_header(args$title),
        bslib::card_body(shiny::markdown(args$text))
      )
    }
  )
}

component_data_table <- function(data) {
  genui_component(
    name = "data_table",
    description = paste(
      "An interactive, sortable table of the live data.",
      "Use it when the user wants to see rows, not summaries."
    ),
    args = list(
      columns = ellmer::type_array(
        column_arg(data, "A column to include."),
        "Columns to show, in order. Omit to show all columns.",
        required = FALSE
      ),
      page_size = ellmer::type_integer(
        "Rows per page (default 10).",
        required = FALSE
      )
    ),
    ui = function(id, args) {
      ns <- shiny::NS(id)
      bslib::card(DT::DTOutput(ns("table")), full_screen = TRUE)
    },
    server = function(id, args, data) {
      shiny::moduleServer(id, function(input, output, session) {
        output$table <- DT::renderDT({
          df <- data()
          shiny::req(is.data.frame(df))
          columns <- unlist(args$columns) %||% names(df)
          DT::datatable(
            df[, columns, drop = FALSE],
            options = list(pageLength = args$page_size %||% 10L),
            rownames = FALSE,
            fillContainer = TRUE
          )
        })
      })
    },
    check = function(args, data) {
      for (column in unlist(args$columns)) {
        problem <- check_column(data, column)
        if (!is.null(problem)) {
          return(problem)
        }
      }
      NULL
    },
    width = "full"
  )
}

component_scatter_plot <- function(data) {
  genui_component(
    name = "scatter_plot",
    description = paste(
      "A scatter plot of two numeric columns, optionally colored by a third",
      "column. Use it to show relationships between variables."
    ),
    args = list(
      x = column_arg(data, "Column on the x axis.", numeric_only = TRUE),
      y = column_arg(data, "Column on the y axis.", numeric_only = TRUE),
      color = column_arg(
        data,
        "Column mapped to point color. Use \"none\" (or omit) for no color mapping.",
        required = FALSE,
        extra = "none"
      ),
      title = ellmer::type_string("Plot title.", required = FALSE)
    ),
    ui = function(id, args) {
      ns <- shiny::NS(id)
      bslib::card(
        bslib::card_header(args$title %||% paste(args$y, "vs.", args$x)),
        shiny::plotOutput(ns("plot"), height = "320px"),
        full_screen = TRUE
      )
    },
    server = function(id, args, data) {
      shiny::moduleServer(id, function(input, output, session) {
        output$plot <- shiny::renderPlot({
          df <- data()
          shiny::req(is.data.frame(df))
          p <- ggplot2::ggplot(
            df,
            ggplot2::aes(x = .data[[args$x]], y = .data[[args$y]])
          )
          color <- args$color
          if (!is.null(color) && !identical(color, "none")) {
            # Few distinct values read better as a discrete scale.
            values <- df[[color]]
            if (is.numeric(values) && length(unique(values)) <= 8) {
              values <- factor(values)
            }
            p <- p + ggplot2::geom_point(
              ggplot2::aes(color = values),
              size = 2.5,
              alpha = 0.8
            ) +
              ggplot2::labs(color = color)
          } else {
            p <- p + ggplot2::geom_point(size = 2.5, alpha = 0.8)
          }
          p + ggplot2::theme_minimal(base_size = 14)
        })
      })
    },
    check = function(args, data) {
      check_column(data, args$x, numeric = TRUE) %||%
        check_column(data, args$y, numeric = TRUE) %||%
        if (!identical(args$color, "none")) check_column(data, args$color)
    },
    width = "wide"
  )
}

component_histogram <- function(data) {
  genui_component(
    name = "histogram",
    description = paste(
      "A histogram of one numeric column with an embedded bin-count slider",
      "the user can drag to explore granularity themselves.",
      "Use it to show a distribution."
    ),
    args = list(
      column = column_arg(data, "Column to plot.", numeric_only = TRUE),
      bins = ellmer::type_integer(
        "Initial number of bins, between 5 and 60 (default 30). The user can change it with the slider afterwards.",
        required = FALSE
      ),
      title = ellmer::type_string("Plot title.", required = FALSE)
    ),
    ui = function(id, args) {
      ns <- shiny::NS(id)
      bins <- min(60L, max(5L, args$bins %||% 30L))
      bslib::card(
        bslib::card_header(
          args$title %||% paste("Distribution of", args$column)
        ),
        shiny::plotOutput(ns("plot"), height = "300px"),
        shiny::sliderInput(
          ns("bins"),
          "Number of bins",
          min = 5L,
          max = 60L,
          value = bins,
          step = 1L,
          width = "100%"
        ),
        full_screen = TRUE
      )
    },
    server = function(id, args, data) {
      shiny::moduleServer(id, function(input, output, session) {
        output$plot <- shiny::renderPlot({
          df <- data()
          shiny::req(is.data.frame(df), input$bins)
          ggplot2::ggplot(df, ggplot2::aes(x = .data[[args$column]])) +
            ggplot2::geom_histogram(
              bins = input$bins,
              fill = "#447099",
              color = "white"
            ) +
            ggplot2::theme_minimal(base_size = 14)
        })
      })
    },
    check = function(args, data) {
      check_column(data, args$column, numeric = TRUE)
    },
    width = "wide"
  )
}
