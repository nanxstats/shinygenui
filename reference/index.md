# Package index

## Components and catalogs

Define the finite set of typed components the model can render.

- [`genui_component()`](https://nanx.me/shinygenui/reference/genui_component.md)
  : Define a generative UI component
- [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md)
  : Collect components into a catalog

## Built-in components

Add ready-made components and layouts to a catalog.

- [`genui_components_bslib()`](https://nanx.me/shinygenui/reference/genui_components_bslib.md)
  : Starter component pack built on bslib
- [`genui_card_row()`](https://nanx.me/shinygenui/reference/genui_card_row.md)
  : Container component: a titled row of cards

## Shiny integration

Create a generative UI canvas and connect it to an ellmer chat.

- [`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md)
  : Canvas container for generated components
- [`genui_server()`](https://nanx.me/shinygenui/reference/genui_server.md)
  : Server logic for a generative UI canvas
- [`genui_prompt()`](https://nanx.me/shinygenui/reference/genui_prompt.md)
  : Assemble the system prompt from a catalog

## Trace and replay

Capture and restore the validated operations that produced a canvas.

- [`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md)
  : Read the ordered call trace of a canvas
- [`genui_replay()`](https://nanx.me/shinygenui/reference/genui_replay.md)
  : Rebuild a canvas from a saved trace, no LLM required

## Dispatch

Construct, validate, and plan model-issued tool calls without Shiny or
an LLM.

- [`genui_call()`](https://nanx.me/shinygenui/reference/genui_call.md) :
  Create a normalized tool call
- [`genui_dispatch()`](https://nanx.me/shinygenui/reference/genui_dispatch.md)
  : Validate one tool call and plan its effect
