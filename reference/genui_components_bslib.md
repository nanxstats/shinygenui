# Starter component pack built on bslib

A small, general-purpose catalog: a value box, a Markdown card, a data
table, a scatter plot, and a histogram with an embedded bin-count slider
(the reference interactive component: dragging the slider re-renders at
Shiny speed with no LLM round trip). Pass the result to
[`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md),
optionally alongside your own components.

## Usage

``` r
genui_components_bslib(data = NULL)
```

## Arguments

- data:

  Optional data frame used to ground column arguments as enums at
  catalog build time. Typically the same data your
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
  `data` reactive returns. With `NULL`, column arguments are free-form
  strings validated only by the `check()` hooks.

## Value

A list of
[`genui_component()`](https://nanx.me/shinygenui/reference/genui_component.md)
objects.

## Details

When `data` is supplied, column arguments become enums of the actual
column names, so a hallucinated column is a schema violation the model
must correct. Each component also validates columns against the live
data through its `check()` hook at render time.

## Examples

``` r
catalog <- genui_catalog(genui_components_bslib(data = mtcars))
names(catalog)
#> [1] "value_box"     "markdown_card" "data_table"    "scatter_plot" 
#> [5] "histogram"    
```
