# Server logic for a generative UI canvas

Wires a
[`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md)
to an ellmer `Chat`: compiles every component into a schema-validated
tool, registers the built-in lifecycle tools (`update_component`,
`remove_component`, `clear_canvas`), installs the assembled system
prompt, and executes validated tool calls against the
[`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md)
with the matching `id`. Components stream onto the canvas progressively
as the model emits tool calls; validation and rendering failures are
returned to the model as tool errors and never crash the session.

## Usage

``` r
genui_server(
  id,
  catalog,
  chat,
  data = NULL,
  chat_id = NULL,
  greeting = NULL,
  system_prompt = NULL
)
```

## Arguments

- id:

  Module id, matching the
  [`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md)
  `id`.

- catalog:

  A
  [`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md).

- chat:

  An ellmer `Chat` object (any provider). Its system prompt is replaced
  with `system_prompt`.

- data:

  A reactive (or function) returning the app's current data object. It
  is passed to component `server()` functions and, isolated, to
  `check()` hooks at validation time.

- chat_id:

  Id of a
  [`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html)
  placed in the UI at the same namespace level as
  [`genui_canvas()`](https://nanx.me/shinygenui/reference/genui_canvas.md),
  or `NULL` (default) to manage the chat loop yourself.

- greeting:

  Optional markdown string shown as the assistant's first message (only
  used when `chat_id` is set). It is display-only and never sent to the
  model.

- system_prompt:

  System prompt to install on `chat`. Defaults to
  [`genui_prompt()`](https://nanx.me/shinygenui/reference/genui_prompt.md)
  of the catalog; use `genui_prompt(catalog, context = ...)` to add app
  context, or pass any string to take full control.

## Value

(Invisibly) a list with `chat` (the wired `Chat`), and the reactives
`trace` (the ordered call trace, see
[`genui_trace()`](https://nanx.me/shinygenui/reference/genui_trace.md))
and `instances` (the live instance state, a named list keyed by id).

## Details

With `chat_id`, the package also runs the chat loop for a
[`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html)
you placed in the UI: user input is streamed through
`chat$stream_async()` inside a
[shiny::ExtendedTask](https://rdrr.io/pkg/shiny/man/ExtendedTask.html)
(so other sessions never block) and appended with
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html),
with cancel support. With `chat_id = NULL` you run your own loop on
`chat`; the registered tools work all the same.

Create the `Chat` object inside your server function, one per session.
Sharing a single `Chat` across sessions would cross-wire the tool
closures and leak conversation history between users.

## Update semantics

`update_component` re-instantiates the component's module with the
merged arguments inside the instance's stable shell: same canvas
position, same ids, no page flicker. Because the module restarts,
embedded input state (like the starter histogram's bin slider) resets to
its defaults on update; snapshotting and restoring embedded input values
across updates is explicitly future work.

## Error feedback

Any failure while handling a tool call — schema validation, a
component's `check()` hook, or a rendering error — is signaled as a
regular R condition. ellmer catches it and returns
[`conditionMessage()`](https://rdrr.io/r/base/conditions.html) to the
model as the tool error, so the model can correct its arguments and
retry; the Shiny session itself never crashes, and a failed call never
leaves a half-rendered component behind. Failures are always logged to
the app's server log; set `options(shinygenui.verbose = TRUE)` to also
log successful canvas operations.
