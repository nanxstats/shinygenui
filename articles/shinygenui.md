# Get started with shinygenui

shinygenui adds two things to a Shiny app: a chat panel where people can
ask questions and a canvas where a large language model can add UI
components. The app developer decides which UI components the model may
use and which arguments each one accepts. Together, these components
form a catalog.

Each component in the catalog becomes an
[ellmer](https://ellmer.tidyverse.org) tool. The model builds the
interface by calling these tools with data. It never writes R code, and
shinygenui never evaluates model output. If the model supplies an
invalid argument, such as a column that does not exist, validation
rejects the call. The model receives a useful error and can try again
while the Shiny session keeps running.

## A complete app

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
    chat = ellmer::chat_openai(),
    data = reactive(mtcars),
    chat_id = "chat",
    greeting = "Ask me about the mtcars data.",
    system_prompt = genui_prompt(
      catalog,
      context = "The data is the mtcars dataset included with R."
    )
  )
}

shinyApp(ui, server)
```

The app has three main pieces:

- [`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md)
  creates the space where components appear.
- [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md)
  collects the components the model may use. This example uses the
  components supplied by shinygenui: a value box, a Markdown card, a
  data table, a scatter plot, and a histogram.
- [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
  turns the catalog into tools and adds them to the ellmer `Chat`. It
  also adds tools for changing the canvas, installs the system prompt,
  and connects the model to the
  [`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html)
  in the sidebar.

You can swap
[`ellmer::chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html)
for any provider `ellmer::chat_*()`. Create the `Chat` inside the server
function so that each session gets its own object. This keeps the
conversation and the functions used by its tools separate for each user.

## Defining a component

A component describes what the model can ask for and how Shiny should
display the result:

``` r

histogram <- genui_component(
  name = "histogram",
  description = "A numeric histogram with a slider for the number of bins.",
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

- `name` and `description` tell the model when to use the component.
  Write descriptions that are clear and specific.
- `args` is a named list of ellmer types. A plain string is shorthand
  for
  [`ellmer::type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html).
  You can build the catalog inside the server function, which means its
  choices can depend on values available in the current session. In this
  example, `column` only accepts names that occur in `mtcars`.
  Validation rejects any other name before your code runs.
- `ui(id, args)` returns htmltools tags. `id` is the module id for this
  instance. Use `shiny::NS(id)` for inputs and outputs inside the
  component.
- `server(id, args, data)` is optional. It usually calls
  [`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html),
  as in the example. `data` is the reactive passed to
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).
  The slider is a regular Shiny input, so moving it redraws the plot
  without contacting the model. If the module creates observers, return
  them on their own or in a list. shinygenui will destroy them when it
  updates or removes the component.
- `check(args, data)` runs after argument validation and receives the
  current value of `data`. Return `NULL` to accept the arguments or a
  string to reject them. The model receives this string as an error.

## The component lifecycle

Each component created by the model gets an id such as `c1` or `c2`. The
model receives this id, which lets it refer to the same component later.
shinygenui also gives the model four tools for working with the canvas:

- `update_component(id, args)` changes only the arguments supplied by
  the model, validates the result, and starts the module again in the
  same place. Because the module restarts, its inputs return to their
  default values.
- `remove_component(id)` removes the component. If it is a container,
  this also removes its children.
- `clear_canvas()` empties the canvas.
- `get_canvas_state()` reports each component, its arguments, and the
  current values of its Shiny inputs. It does not change the canvas. The
  model can use this information to see what a user has adjusted.

The system prompt created by
[`genui_prompt()`](https://nanx.me/shinygenui/reference/genui_prompt.md)
asks the model to keep its chat response brief while it adds components.
It also asks the model to update an existing component when the user
refines a request and to avoid filling the canvas with unnecessary
components. Use the `context` argument to explain your app and its data.
Useful context might include a description of the columns, a few sample
rows, or terms that are specific to your organization. shinygenui only
puts raw data in the prompt if you include it yourself.

## Containers

A component declared with `container = TRUE` can hold other components.
The model creates the container first, then passes its id as `parent_id`
when it creates each child.
[`genui_card_row()`](https://nanx.me/shinygenui/reference/genui_card_row.md)
is an example supplied by the package. It creates a titled row that can
group value boxes or plots. Removing a container also removes its
children. See `inst/examples/02-layout/app.R` for a full app.

## Trace and replay

shinygenui records each successful call as a plain list. Together, these
lists describe the current canvas in the order it was built.
[`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md)
returns this record as a reactive, and
[`genui_replay()`](https://nanx.me/shinygenui/reference/genui_replay.md)
passes a saved record through the same validation and rendering code to
rebuild the canvas. You can replay it in a new session without an LLM:

``` r

# In the session that built the canvas
observe({
  saveRDS(genui_trace(session)(), "canvas-trace.rds")
})

# In a later session, no chat anywhere
server <- function(input, output, session) {
  genui_replay(
    readRDS("canvas-trace.rds"),
    catalog = catalog,
    target = "canvas",
    data = reactive(mtcars)
  )
}
```

The same calls produce the same instance ids, and ids are never reused.
The record does not include values from Shiny inputs, so replay restores
those inputs to their defaults.

## When things go wrong

If argument validation, `check()`, or rendering fails, the model
receives an error and can try again. A failed create leaves nothing
behind, and a failed update leaves the existing component unchanged. The
error does not crash the Shiny session. Because the model can only call
components in your catalog, a prompt injection cannot make it run
arbitrary code. Failures are always written to the server log. Set
`options(shinygenui.verbose = TRUE)` to also log successful changes to
the canvas.
