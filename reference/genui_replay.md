# Rebuild a canvas from a saved trace, no LLM required

Folds a trace (from
[`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md),
or the `trace` reactive returned by
[`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md))
through the same validate-and-execute pipeline the model's tool calls
use, recreating every instance in a
[`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md)
with id `target`. Instance ids come back identical because ids are
assigned deterministically and never reused. Embedded inputs return at
their default values: input state is ephemeral by design and not part of
the trace.

## Usage

``` r
genui_replay(
  trace,
  catalog,
  target,
  data = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- trace:

  A trace list, as returned by
  [`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md)
  (already evaluated, not the reactive) or restored via
  [`readRDS()`](https://rdrr.io/r/base/readRDS.html).

- catalog:

  The
  [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md)
  to render with; component names in the trace must exist in it.

- target:

  Module id of the
  [`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md)
  to rebuild into. Use a canvas of its own, not one already driven by
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).

- data:

  Optional reactive (or function) returning the data object, passed to
  component servers and `check()` hooks, as in
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).

- session:

  The Shiny session (defaults to the current reactive domain).

## Value

(Invisibly) a list with reactives `trace` and `instances` describing the
rebuilt canvas, as in
[`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md).

## Details

Entries that no longer validate (for example after the catalog changed)
are skipped with a warning; the rest of the trace still replays. The
target canvas is emptied first, so replaying twice is idempotent.
