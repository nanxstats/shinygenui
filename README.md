# shinygenui

<!-- badges: start -->
[![R-CMD-check](https://github.com/nanxstats/shinygenui/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/nanxstats/shinygenui/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

shinygenui brings declarative generative UI to Shiny.
You define a finite catalog of typed UI components as guardrails.
End users of your deployed app talk to an LLM through a chat panel, and the
model answers by composing instances of those components, streamed
progressively onto a canvas. The model can also update and remove components
it previously created, so the generated view is conversationally mutable,
not append-only.

It is the R/Shiny analogue of Vercel's json-render and Google's A2UI
but intentionally narrower: one language, one framework, one deployment story.
An regular Shiny app (deployed on Posit Connect for example), with no sidecar
servers, no Node, and no schemas or JSON authored manually.

## How it stays safe

- **Tool calls, not code generation.** Every catalog entry compiles to an
  [ellmer](https://ellmer.tidyverse.org) tool. The model "renders" a
  component by calling its tool with typed arguments; it never emits R code,
  and the package never calls `eval()` or `parse()` on model output.
  Arguments are data, interpreted only by your component functions.
- **Grounded, per-session schemas.** Catalogs can be built inside the server
  function, so argument types can enumerate live facts. For example, the
  columns of the active dataset as enum values. A hallucinated column is a
  schema violation the model has to correct.
- **Error feedback loop.** Validation and rendering failures go back to the
  model as tool errors with actionable messages; the session never crashes.
  A prompt-injection worst case is an ugly dashboard, not code execution.

## Installation

``` r
# install.packages("pak")
pak::pak("nanxstats/shinygenui")
```

## Example

A complete app: chat sidebar, canvas, and a starter catalog grounded on
`mtcars`. Ask for "mpg vs. hp and a value box with the average mpg", then
"color the scatter by cylinders". The existing plot updates in place.

``` r
library(shiny)
library(bslib)
library(shinygenui)

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
    chat = ellmer::chat_anthropic(), # any ellmer provider works
    data = reactive(mtcars),
    chat_id = "chat",
    system_prompt = genui_prompt(catalog, context = "The data is mtcars.")
  )
}

shinyApp(ui, server)
```

The starter pack includes a histogram whose bin-count slider is a live Shiny
input embedded in the generated component: dragging it re-renders instantly,
with no LLM round trip.

Defining your own component is one call:

``` r
genui_component(
  name = "value_box",
  description = "A box highlighting one summary statistic.",
  args = list(
    title = "Short label above the value.",
    column = ellmer::type_enum(names(mtcars), "Column to summarize.")
  ),
  ui = function(id, args) { ... },       # htmltools tags; NS(id) for inputs
  server = function(id, args, data) { ... } # optional moduleServer()
)
```

Runnable example apps live in `inst/examples/`: `01-mtcars-explorer`
(the basics) and `02-layout` (container rows, plus rebuilding a canvas from
its trace with `genui_replay()`, no LLM required).

## Learn more

- `vignette("shinygenui")` walks through the full model: catalogs, grounded
  schemas, lifecycle tools, embedded interactivity, and trace/replay.
- `DESIGN.md` in the repository documents the architecture.

## License

MIT
