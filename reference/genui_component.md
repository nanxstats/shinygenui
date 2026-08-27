# Define a generative UI component

A component is one entry in the finite catalog that constrains what the
model can render. It couples a model-facing tool schema (`name`,
`description`, typed `args`) with developer-written rendering code: a
`ui` function plus an optional `server` function, instantiated together
as a dynamic Shiny module every time the model creates or updates an
instance. The model only ever supplies data arguments validated against
the declared types; it never emits code.

## Usage

``` r
genui_component(
  name,
  description,
  args = list(),
  ui,
  server = NULL,
  check = NULL,
  container = FALSE,
  width = c("auto", "wide", "full")
)
```

## Arguments

- name:

  Tool name the model sees. A snake_case string: lowercase letters,
  digits, and underscores, starting with a letter. Must be unique within
  a catalog and must not collide with the built-in lifecycle tools
  (`update_component`, `remove_component`, `clear_canvas`).

- description:

  One to three sentences telling the model what the component shows and
  when to use it. This is the model-facing documentation for the
  component, so write it well.

- args:

  Named list of ellmer type specifications (for example
  [`ellmer::type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html),
  [`ellmer::type_enum()`](https://ellmer.tidyverse.org/reference/type_boolean.html))
  describing the arguments the model may supply. As a shorthand, a plain
  string is promoted to `ellmer::type_string(<string>)`. Argument names
  `id` and `parent_id` are reserved by the package. Catalogs are often
  built inside the Shiny server function so enums can enumerate live
  facts, such as the column names of the active dataset.

- ui:

  `function(id, args)` returning an
  [`htmltools::tag()`](https://rstudio.github.io/htmltools/reference/builder.html)
  (or tag list). `id` is the fully namespaced module id for this
  instance; use `shiny::NS(id)` to namespace any embedded inputs and
  outputs. `args` is the validated argument list.

- server:

  Optional `function(id, args, data)` that calls
  [`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html)
  to wire outputs and embedded inputs. `data` is the reactive passed to
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).
  If the module creates observers, include them in the module's return
  value (alone or inside a list) so the package can destroy them when
  the instance is updated or removed. A `reactives` element in the
  return value is stored in the instance registry keyed by instance id;
  nothing reads it in v0.1, it is the hook for cross-component
  reactivity in a later release.

- check:

  Optional `function(args, data)` for semantic validation beyond the
  JSON schema. Return `NULL` when `args` are acceptable, or a string
  describing the problem; the string is returned to the model as a tool
  error so it can self-correct.

- container:

  If `TRUE`, this component can host child instances: its `ui` must
  render an element with id `shiny::NS(id, "slot")`, and other
  components may target it by passing the instance's id as `parent_id`.

- width:

  Layout hint for the canvas grid: `"auto"` (default), `"wide"`, or
  `"full"`.

## Value

A `genui_component` object.

## Examples

``` r
genui_component(
  name = "note_card",
  description = "A card showing a short markdown note. Use for narrative
    text that should live on the canvas rather than in the chat.",
  args = list(
    title = "A short title for the card.",
    text = ellmer::type_string("The markdown body text.")
  ),
  ui = function(id, args) {
    htmltools::div(
      htmltools::h5(args$title),
      htmltools::p(args$text)
    )
  }
)
#> <genui_component> "note_card"
#> A card showing a short markdown note. Use for narrative text that should live
#> on the canvas rather than in the chat.
#> args: "title" and "text"
```
