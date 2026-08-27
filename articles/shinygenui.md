# shinygenui

``` r

library(shinygenui)
```

shinygenui adds a generative UI surface to a Shiny app: a chat panel
where end users ask questions, and a canvas where a large language model
answers by composing UI components. The crucial constraint is that the
model can only render what you allow. You define a finite catalog of
typed components; each one compiles to an
[ellmer](https://ellmer.tidyverse.org) tool, and the model “renders” by
calling those tools with plain data arguments. It never writes R code,
and the package never evaluates model output. If the model supplies a
bad argument — a column that does not exist, a value outside an enum —
the call fails validation and the error message goes back to the model
to correct, while your session keeps running.

## A complete app

``` r

library(shiny)
library(bslib)

ui <- page_sidebar(
  title = "mtcars explorer",
  sidebar = sidebar(width = 380, shinychat::chat_ui("chat", height = "100%")),
  genui_canvas("canvas")
)

server <- function(input, output, session) {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))

  genui_server(
    "canvas",
    catalog = catalog,
    chat = ellmer::chat_anthropic(),
    data = reactive(mtcars),
    chat_id = "chat",
    greeting = "Ask me about the mtcars data.",
    system_prompt = genui_prompt(
      catalog,
      context = "The data is R's built-in mtcars dataset."
    )
  )
}

shinyApp(ui, server)
```

Three pieces do all the work:

- `genui_canvas("canvas")` is the container components land in.
- [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md)
  collects the components the model may use — here the bslib starter
  pack: a value box, a markdown card, a data table, a scatter plot, and
  a histogram.
- [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
  compiles the catalog into tools, registers them (plus the built-in
  lifecycle tools) on the ellmer `Chat`, installs the system prompt, and
  runs the chat loop against the
  [`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html)
  you placed in the sidebar.

Any ellmer provider works: swap
[`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html)
for
[`ellmer::chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html),
[`ellmer::chat_ollama()`](https://ellmer.tidyverse.org/reference/chat_ollama.html),
and so on. Create the `Chat` inside the server function — one per
session — so tool closures and conversation history are never shared
between users.

## Defining a component

A component couples the model-facing schema with your rendering code:

``` r

histogram <- genui_component(
  name = "histogram",
  description = "A histogram of one numeric column with a bin-count slider.",
  args = list(
    column = ellmer::type_enum(names(mtcars), "Column to plot."),
    bins = ellmer::type_integer("Initial number of bins.", required = FALSE)
  ),
  ui = function(id, args) {
    ns <- shiny::NS(id)
    bslib::card(
      shiny::plotOutput(ns("plot")),
      shiny::sliderInput(ns("bins"), "Bins", 5, 60, args$bins %||% 30)
    )
  },
  server = function(id, args, data) {
    shiny::moduleServer(id, function(input, output, session) {
      output$plot <- shiny::renderPlot({
        hist(data()[[args$column]], breaks = input$bins)
      })
    })
  },
  check = function(args, data) {
    if (!is.numeric(data[[args$column]])) {
      paste0("Column \"", args$column, "\" is not numeric.")
    }
  }
)
```

- `name` and `description` are product surface: they are exactly what
  the model reads when deciding which tool to call. Write them like
  documentation.
- `args` is a named list of ellmer types. A plain string is shorthand
  for
  [`ellmer::type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html).
  Because catalogs are ordinary R values, you can build them *inside*
  the server function and ground enums on live facts: above, `column`
  enumerates the actual column names, so a hallucinated column is
  rejected by schema before your code ever runs.
- `ui(id, args)` returns htmltools tags. `id` is the instance’s module
  id; namespace embedded inputs and outputs with `shiny::NS(id)`.
- `server(id, args, data)` is optional and wraps
  [`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html).
  `data` is the reactive you passed to
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).
  Embedded inputs like the slider here are real Shiny inputs wired to
  this instance’s own module: dragging the slider re-renders at Shiny
  speed with zero LLM traffic. If your module creates observers, return
  them (alone or in a list) so they can be destroyed when the instance
  is updated or removed.
- `check(args, data)` runs after schema validation with the current data
  value. Return `NULL` to accept or a string to reject; the string
  becomes the tool error the model reads.

## The component lifecycle

Every created instance gets a stable id (`c1`, `c2`, …) that is returned
to the model in the tool result. Alongside your catalog, four built-in
tools are always registered:

- `update_component(id, args)` merges partial arguments over the current
  ones, re-validates, and re-instantiates the module inside the
  instance’s stable shell — same canvas position, no flicker. Because
  the module restarts, embedded input state resets to defaults on
  update; snapshot and restore across updates is future work.
- `remove_component(id)` destroys the instance (and, for containers, its
  children).
- `clear_canvas()` empties the canvas.
- `get_canvas_state()` is read-only: it reports every instance with its
  arguments and the live values of its embedded inputs, so the model can
  see what the user has adjusted before acting.

The packaged system prompt (see
[`genui_prompt()`](https://nanx.me/shinygenui/reference/genui_prompt.md))
instructs the model to narrate briefly in chat while placing visuals via
tools, to reuse `update_component` when the user refines an existing
view, and to prefer few, dense components. Add app-specific grounding
through the `context` argument — a schema description, a few sample
rows, a business glossary. Raw data is never put in the prompt unless
you put it there.

## Containers

A component declared with `container = TRUE` renders a slot other
components can target: the model creates the container first, then
passes its instance id as `parent_id` when creating children.
[`genui_card_row()`](https://nanx.me/shinygenui/reference/genui_card_row.md)
is the packaged example — a titled row that groups value boxes or plots.
Removing a container removes its children. See
`inst/examples/02-layout/app.R` for a full app.

## Trace and replay

Every validated call appends to an ordered trace of plain, serializable
lists: the spec of record for the canvas.
[`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md)
gives you a reactive read of it, and
[`genui_replay()`](https://nanx.me/shinygenui/reference/genui_replay.md)
folds a saved trace through the same validate-and-execute pipeline to
rebuild the canvas — in a fresh session, with no LLM configured:

``` r

# in the session that built the canvas
observe({
  saveRDS(genui_trace(session)(), "canvas-trace.rds")
})

# in a later session, no chat anywhere
server <- function(input, output, session) {
  genui_replay(
    readRDS("canvas-trace.rds"),
    catalog = catalog,
    target = "canvas",
    data = reactive(mtcars)
  )
}
```

Instance ids come back identical (id assignment is deterministic and ids
are never reused). Embedded input values are intentionally *not*
recorded: replay restores components with inputs at their defaults.

## When things go wrong

Every failure while handling a tool call — schema validation, `check()`
hooks, rendering errors — becomes a tool error the model reads and
recovers from. Failed creates roll back completely; failed updates leave
the existing instance untouched. The Shiny session itself never crashes,
and the worst case of a prompt injection is an ugly dashboard, not code
execution. Failures are always written to the server log; set
`options(shinygenui.verbose = TRUE)` to also log successful canvas
operations.
