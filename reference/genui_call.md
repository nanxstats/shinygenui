# Create a normalized tool call

A `genui_call` is the normalized representation of one model-issued tool
call: the tool name plus its arguments as plain data.
[`genui_dispatch()`](https://nanx.me/shinygenui/reference/genui_dispatch.md)
consumes these. In production they are produced by the compiled ellmer
tools; in tests and replays you can hand-build them.

## Usage

``` r
genui_call(tool, args = list())
```

## Arguments

- tool:

  Tool name: a component name from the catalog, or one of the built-ins
  `"update_component"`, `"remove_component"`, `"clear_canvas"`.

- args:

  Named list of arguments as supplied by the model. For
  `update_component`, `args` must contain `id` and `args` (the partial
  arguments to merge, as a named list or a JSON object string).

## Value

A `genui_call` object.

## Examples

``` r
genui_call("scatter_plot", list(x = "mpg", y = "hp"))
#> $tool
#> [1] "scatter_plot"
#> 
#> $args
#> $args$x
#> [1] "mpg"
#> 
#> $args$y
#> [1] "hp"
#> 
#> 
#> attr(,"class")
#> [1] "genui_call"
genui_call("update_component", list(id = "c1", args = list(x = "wt")))
#> $tool
#> [1] "update_component"
#> 
#> $args
#> $args$id
#> [1] "c1"
#> 
#> $args$args
#> $args$args$x
#> [1] "wt"
#> 
#> 
#> 
#> attr(,"class")
#> [1] "genui_call"
genui_call("remove_component", list(id = "c1"))
#> $tool
#> [1] "remove_component"
#> 
#> $args
#> $args$id
#> [1] "c1"
#> 
#> 
#> attr(,"class")
#> [1] "genui_call"
```
