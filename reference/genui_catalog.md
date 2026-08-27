# Collect components into a catalog

A catalog is the finite set of components the model is allowed to
render. Each component compiles to one
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html);
the built-in lifecycle tools (`update_component`, `remove_component`,
`clear_canvas`) are registered alongside it by
[`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).

## Usage

``` r
genui_catalog(...)
```

## Arguments

- ...:

  [`genui_component()`](https://nanx.me/shinygenui/reference/genui_component.md)
  objects, or lists of them (so component packs such as
  [`genui_components_bslib()`](https://nanx.me/shinygenui/reference/genui_components_bslib.md)
  can be passed directly).

## Value

A `genui_catalog` object: a named list of components, keyed by component
name.

## Examples

``` r
note <- genui_component(
  name = "note_card",
  description = "A card showing a short note.",
  args = list(text = "The note text."),
  ui = function(id, args) htmltools::p(args$text)
)
catalog <- genui_catalog(note)
names(catalog)
#> [1] "note_card"
```
