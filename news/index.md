# Changelog

## shinygenui 0.1.0

### New features

- Initial release: catalog-constrained generative UI for Shiny.
- Define components with
  [`genui_component()`](https://nanx.me/shinygenui/reference/genui_component.md)
  and collect them with
  [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md);
  each entry compiles to a schema-validated ellmer tool.
- [`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md) +
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
  stream model-composed components into a running app, with built-in
  `update_component`, `remove_component`, `clear_canvas`, and read-only
  `get_canvas_state` lifecycle tools.
- Pure
  [`genui_dispatch()`](https://nanx.me/shinygenui/reference/genui_dispatch.md)
  core validates and plans every model-issued call; failures return to
  the model as tool errors and never crash the session.
- [`genui_components_bslib()`](https://nanx.me/shinygenui/reference/genui_components_bslib.md)
  starter pack (value box, markdown card, data table, scatter plot,
  histogram with an embedded bin-count slider) and the
  [`genui_card_row()`](https://nanx.me/shinygenui/reference/genui_card_row.md)
  container.
- [`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md)
  records every validated call;
  [`genui_replay()`](https://nanx.me/shinygenui/reference/genui_replay.md)
  rebuilds a canvas from a saved trace with no LLM configured.
