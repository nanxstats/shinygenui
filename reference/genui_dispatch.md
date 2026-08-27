# Validate one tool call and plan its effect

The pure core of shinygenui: given the catalog, one normalized call, and
the current instance state, either return a plan describing what should
happen (create, update, remove, or clear) or signal a classed error
whose message is written for the model to read and correct. No Shiny
session, registry mutation, or LLM is involved; the Shiny executor
applies the returned plan.

## Usage

``` r
genui_dispatch(catalog, call, state, data = NULL)
```

## Arguments

- catalog:

  A
  [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md).

- call:

  A [`genui_call()`](https://nanx.me/shinygenui/reference/genui_call.md)
  (or a plain list with `tool` and `args`).

- state:

  Current instance state: a `GenuiRegistry` or a list with `instances`
  (a named list of `list(component, args, parent_id)` keyed by instance
  id) and `next_id` (integer).

- data:

  Current value of the app's data object, passed to component `check()`
  hooks. Typically `shiny::isolate(data())` at call time.

## Value

A `genui_plan` object, a list with at least `action` (one of `"create"`,
`"update"`, `"remove"`, `"clear"`) plus the fields the executor needs:
`id`, `component`, `args` (full args to render), `delta` (validated
partial args, updates only), `parent_id`, and `ids` (teardown order,
removes and clears only).

## Examples

``` r
catalog <- genui_catalog(
  genui_component(
    name = "note_card",
    description = "A card showing a short note.",
    args = list(text = "The note text."),
    ui = function(id, args) htmltools::p(args$text)
  )
)
state <- list(instances = list(), next_id = 1L)
genui_dispatch(catalog, genui_call("note_card", list(text = "hi")), state)
#> $action
#> [1] "create"
#> 
#> $id
#> [1] "c1"
#> 
#> $component
#> [1] "note_card"
#> 
#> $args
#> $args$text
#> [1] "hi"
#> 
#> 
#> $parent_id
#> NULL
#> 
#> attr(,"class")
#> [1] "genui_plan"
```
