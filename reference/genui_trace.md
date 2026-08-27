# Read the ordered call trace of a canvas

The trace is the spec of record for a canvas: every validated call the
model made (create, update, remove, clear), in order, as plain
JSON-friendly lists.
[`genui_replay()`](https://nanx.me/shinygenui/reference/genui_replay.md)
can rebuild the canvas from it with no LLM configured. Embedded input
state is intentionally ephemeral and never recorded.

## Usage

``` r
genui_trace(session = shiny::getDefaultReactiveDomain(), id = NULL)
```

## Arguments

- session:

  The Shiny session (defaults to the current reactive domain).

- id:

  The
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
  module id to read, relative to `session`. May be omitted when the
  session has exactly one canvas.

## Value

A reactive expression returning the trace: a list of entries of the form
`list(op = "create", id = "c1", component = "...", args = list(...))`
(plus `parent_id` for children; `update` entries carry the validated
argument delta). Persist it with
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) to replay in a later
session.
