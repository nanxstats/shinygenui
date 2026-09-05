# shinygenui (development version)

## Dependencies

- Require ellmer >= 0.4.1 for `stream_controller()`, which powers chat
  cancellation.

## Branding

- Add a hex sticker logo with a p5.brush watercolor polygon background (#14).

## Examples

- Example and acceptance test apps now read their model and reasoning effort
  from the required `SHINYGENUI_MODEL` and `SHINYGENUI_EFFORT` environment
  variables instead of relying on defaults (#9).
- The `01-mtcars-explorer` example now offers prompt buttons above the
  chat composer. A click fills and focuses the composer without submitting (#10).

## Documentation

- The README now includes a recording of the mtcars explorer example (#11).
- Code examples now consistently use the same model provider while continuing
  to support any ellmer provider (#8).

# shinygenui 0.1.0

## New features

- Use `genui_component()` to define a component and `genui_catalog()` to
  collect components into a catalog. Each component becomes an ellmer tool
  with validated arguments.
- Use `genui_canvas()` and `genui_server()` to let the model add components to
  a running app. The included tools let it update or remove a component,
  clear the canvas, and inspect the current canvas.
- Every call from the model passes through `genui_dispatch()` before it can
  change the canvas. If a call fails, the model receives the error and the
  Shiny session keeps running.
- `genui_components_bslib()` provides a value box, Markdown card, data table,
  scatter plot, and histogram with a slider for the number of bins.
  `genui_card_row()` provides a container for arranging these components.
- `genui_trace()` records each successful call. `genui_replay()` can rebuild
  the canvas from that record without an LLM.
