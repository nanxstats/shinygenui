# shinygenui 0.1.0

## New features

- Initial release: catalog-constrained generative UI for Shiny.
- Define components with `genui_component()` and collect them with
  `genui_catalog()`; each entry compiles to a schema-validated ellmer tool.
- `genui_canvas()` + `genui_server()` stream model-composed components into
  a running app, with built-in `update_component`, `remove_component`,
  `clear_canvas`, and read-only `get_canvas_state` lifecycle tools.
- Pure `genui_dispatch()` core validates and plans every model-issued call;
  failures return to the model as tool errors and never crash the session.
- `genui_components_bslib()` starter pack (value box, markdown card, data
  table, scatter plot, histogram with an embedded bin-count slider) and the
  `genui_card_row()` container.
- `genui_trace()` records every validated call; `genui_replay()` rebuilds a
  canvas from a saved trace with no LLM configured.
