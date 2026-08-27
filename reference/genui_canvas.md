# Canvas container for generated components

Place this anywhere in your UI, typically as the main content next to a
[`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html)
sidebar. Components emitted by the model are inserted into it
progressively as tool calls complete. Pair it with a
[`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
call using the same `id`.

## Usage

``` r
genui_canvas(id, ..., placeholder = "Components will appear here.")
```

## Arguments

- id:

  Module id, matching the `id` passed to
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).

- ...:

  Attributes and initial children added to the canvas `<div>`.

- placeholder:

  Text shown while the canvas is empty.

## Value

An
[`htmltools::tag()`](https://rstudio.github.io/htmltools/reference/builder.html)
object.

## Examples

``` r
genui_canvas("canvas")
#> <div id="canvas-canvas" class="genui-canvas" data-placeholder="Components will appear here."></div>
```
