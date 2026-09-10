# Changelog

## shinygenui (development version)

### Chat integration

- Require shinychat \>= 0.5.0 and delegate streaming, cancellation, and
  attachments to `chat_server()`. Conversation history stays disabled
  until it can restore the canvas and registry together. The package no
  longer directly imports {promises}
  ([\#21](https://github.com/nanxstats/shinygenui/issues/21)).
- Greetings now use the shinychat welcome message API and disappear
  after the first user message. They remain display only and are not
  sent to the model
  ([\#21](https://github.com/nanxstats/shinygenui/issues/21)).
- Use
  [`shinychat::tool_result_display()`](https://posit-dev.github.io/shinychat/r/reference/tool_result_display.html)
  for tool results and present tense titles for running tools. The
  mtcars example uses the input toolbar to keep its prompt buttons above
  the composer
  ([\#21](https://github.com/nanxstats/shinygenui/issues/21)).

### Dependencies

- Require ellmer \>= 0.4.1 for `stream_controller()`, which powers chat
  cancellation
  ([\#17](https://github.com/nanxstats/shinygenui/issues/17)).

### Branding

- Add a hex sticker logo with a p5.brush watercolor polygon background
  ([\#14](https://github.com/nanxstats/shinygenui/issues/14)).

### Examples

- Example and acceptance test apps now read their model and reasoning
  effort from the required `SHINYGENUI_MODEL` and `SHINYGENUI_EFFORT`
  environment variables instead of relying on defaults
  ([\#9](https://github.com/nanxstats/shinygenui/issues/9)).
- The `01-mtcars-explorer` example now offers prompt buttons above the
  chat composer. A click fills and focuses the composer without
  submitting
  ([\#10](https://github.com/nanxstats/shinygenui/issues/10)).

### Documentation

- The README now includes a recording of the mtcars explorer example
  ([\#11](https://github.com/nanxstats/shinygenui/issues/11)).
- Code examples now consistently use the same model provider while
  continuing to support any ellmer provider
  ([\#8](https://github.com/nanxstats/shinygenui/issues/8)).

## shinygenui 0.1.0

CRAN release: 2026-09-09

### New features

- Use
  [`genui_component()`](https://nanx.me/shinygenui/reference/genui_component.md)
  to define a component and
  [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md)
  to collect components into a catalog. Each component becomes an ellmer
  tool with validated arguments.
- Use
  [`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md)
  and
  [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
  to let the model add components to a running app. The included tools
  let it update or remove a component, clear the canvas, and inspect the
  current canvas.
- Every call from the model passes through
  [`genui_dispatch()`](https://nanx.me/shinygenui/reference/genui_dispatch.md)
  before it can change the canvas. If a call fails, the model receives
  the error and the Shiny session keeps running.
- [`genui_components_bslib()`](https://nanx.me/shinygenui/reference/genui_components_bslib.md)
  provides a value box, Markdown card, data table, scatter plot, and
  histogram with a slider for the number of bins.
  [`genui_card_row()`](https://nanx.me/shinygenui/reference/genui_card_row.md)
  provides a container for arranging these components.
- [`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md)
  records each successful call.
  [`genui_replay()`](https://nanx.me/shinygenui/reference/genui_replay.md)
  can rebuild the canvas from that record without an LLM.
