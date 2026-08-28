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
