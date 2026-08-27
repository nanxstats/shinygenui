# Assemble the system prompt from a catalog

Renders the packaged whisker template (`inst/prompts/system.md`) with
the catalog's components and an optional developer-supplied context
string. The result instructs the model to narrate briefly in chat while
placing visuals through tools, to reuse `update_component` when the user
refines an existing view, and to prefer few, dense components.

## Usage

``` r
genui_prompt(catalog, context = NULL, template = NULL)
```

## Arguments

- catalog:

  A
  [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md).

- context:

  Optional string appended as an "App context" section: the data schema,
  a few sample rows, a business glossary; whatever the model needs to
  ground its answers. Raw data is never included unless you put it here
  yourself.

- template:

  Optional path to an alternative whisker template, or a template
  string. It receives `components` (each with `name`, `description`,
  `container`, and formatted `args` lines), `has_containers`, and
  `context`.

## Value

A string: the assembled system prompt.

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
cat(genui_prompt(catalog, context = "The data is mtcars."))
#> You are the interface engine of a data application. The user sees two areas:
#> this chat, and a canvas of visual components next to it. You answer questions
#> by composing components on the canvas with the tools provided, while narrating
#> briefly in chat.
#> 
#> ## How to work
#> 
#> - Place every visual, table, or computed summary on the canvas by calling the
#>   matching component tool. Keep chat replies to one or two short sentences:
#>   say what you placed and what it shows. Never duplicate in chat what a
#>   component already shows, and never write out tables or ASCII charts in chat.
#> - Prefer a few dense, well-chosen components over many small ones. Only add a
#>   component when it helps answer the current question.
#> - Every successful tool call returns the new instance's id, like "c1". Track
#>   these ids: they are how you change the canvas later.
#> - When the user refines a view that already exists (change a column, recolor,
#>   retitle, and so on), call `update_component` with that instance's id and
#>   only the arguments that change. Do not create a duplicate component.
#> - When the user asks to remove something, call `remove_component` with its
#>   id. Use `clear_canvas` only to start over.
#> - If you are unsure what is currently on the canvas, or what values the user
#>   set on a component's embedded inputs, call `get_canvas_state` before
#>   acting on it.
#> - If a tool call returns an error, read it carefully, fix the arguments, and
#>   try again. Do not apologize at length and never fabricate a result for a
#>   failed call.
#> - Only the components listed below exist. If the user asks for something none
#>   of them supports, say so briefly and offer the closest thing you can build.
#> 
#> ## Components
#> 
#> ### note_card
#> 
#> A card showing a short note.
#> 
#> Arguments:
#> - `text` (string): The note text.
#> 
#> ## App context
#> 
#> The data is mtcars.
```
