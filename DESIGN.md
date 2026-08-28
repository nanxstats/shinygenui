# shinygenui design

shinygenui lets a language model build a Shiny interface without letting it
write UI code. The app developer provides a fixed catalog of components. When
someone uses the chat, the model can create, update, and remove instances of
those components on a canvas. Components appear as the model continues its
response. The package is similar to Vercel's json-render and Google's A2UI,
but focuses on one language, one framework, and the usual ways of deploying a
Shiny app.

## Layers

1. **Pure core**: `genui_component()`, `genui_catalog()`, and `genui_dispatch()`
   define components and validate their arguments against ellmer types.
   This layer does not depend on Shiny or an LLM. Unit tests use tool calls
   created by hand.
2. **Session state**: `GenuiRegistry` is an R6 object that stores each
   instance's id, component name, current arguments, parent id, observer
   handles, and any reactives returned by its server. It also stores the id
   counter and the ordered trace. This layer changes R state but does not
   change the DOM.
3. **Shiny executor**: this layer turns a plan from `genui_dispatch()` into
   calls to `insertUI()` and `removeUI()`, then starts component modules.
   Every operation receives the Shiny session explicitly.
4. **LLM support**: this layer turns the catalog into `ellmer::tool()`
   objects, adds the tools supplied by shinygenui, builds the system prompt
   with whisker, and runs the shinychat streaming loop.

Stateful objects, such as `GenuiRegistry`, use R6. Declarative values,
such as components, catalogs, plans, and trace entries, are plain S3 lists.
Tool results use ellmer's S7 `ContentToolResult` class. This follows the
same broad division of responsibilities used in querychat.

## Data flow

```
user message → shinychat → chat$stream_async(stream = "content") [ExtendedTask]
  → narrative text from model → chat_append() displays it
  → tool call from model (arguments already checked against the tool schema)
      → compiled tool function turns the arguments into a genui_call
          → genui_dispatch(catalog, call, state)
              checks the component, ids, argument types, and check() result
              returns a plan for create, update, remove, or clear
          → registry applies the change and adds a trace entry
          → executor calls insertUI(..., immediate = TRUE, session = session)
              and withReactiveDomain(session, component$server(...))
      → tool returns ContentToolResult with the id and display information
  → model receives the id and may continue with text or more tool calls
```

If validation, `check()`, or rendering fails, the tool function lets the R
condition propagate. ellmer catches the condition and returns its message to
the model as a tool error. The model can then correct its request in the next
turn. The error does not crash the Shiny session.

The model never writes R code, and shinygenui never calls `eval()` or
`parse()` on model output. Tool arguments are data that only the component
functions supplied by the app developer can interpret.

ellmer runs tools after the assistant turn that requested them is complete,
then begins another assistant turn. Each valid tool call uses `immediate = TRUE`,
so its UI can appear while `chat_append()` is still displaying the surrounding
response. This gives progressive rendering without another transport layer.

## Instances and lifecycle

Each instance receives an id such as `c1` or `c2`. The registry owns the
counter, and it never reuses an id. The instance renders inside a shell such
as `div(id = ns("shell-c1"))`, which is appended to `div(id = ns("canvas"))`.
The component's module id is the instance id inside the namespace of the
shinygenui module. This prevents input ids from colliding.
Once a component is present, its inputs respond through Shiny
without another request to the model.

- **Create**: dispatch assigns the next id. The executor inserts the shell in
  the canvas, or in a container when `parent_id` is supplied, and then runs
  `server(id, args, data)` in the module session.
- **Update**: `update_component(id, args)` uses `modifyList()` to combine the
  supplied arguments with the current arguments, then validates the result.
  The executor destroys the instance's observers, removes the contents of the
  shell, and creates its UI and server again. The shell and its position do not
  change. In version 0.1, Shiny inputs return to their defaults after an update
  because the module starts again. Preserving those values is future work.
- **Remove and clear**: the executor destroys observers and then removes the
  relevant shells. For a container, it removes children before their parent.

### Cleaning up observers

A component's `server` function returns the result of `moduleServer()`.
The registry finds any observers in that value, including observers nested inside lists,
and calls `$destroy()` on them when the component is updated or removed.

If the returned value has an element named `reactives`, the registry stores it
under the instance id. This is a planned hook for version 0.2. It provides one
supported channel for sharing filtered data between components instead of a
general publish and subscribe system. Nothing reads these values in version 0.1.

Shiny cannot unregister output render functions. On update, shinygenui uses the
same ids, so the new render functions replace the old ones. On removal, the old
outputs remain suspended because there is no longer a DOM element bound to them.

## Tools and schemas

Each catalog entry becomes an `ellmer::tool()`. shinygenui generates the
function formals from the component's argument names because ellmer requires
the formals and declared arguments to match exactly.

An app can build its catalog inside the server function. Argument types can
therefore use values that are known in the current session. For example,
a `type_enum` can contain the column names of the current dataset.
If the model invents a column, the tool schema rejects it.

shinygenui also supplies `update_component`, `remove_component`, `clear_canvas`,
and `get_canvas_state`. ellmer cannot express an update schema that varies with
the selected component, so `update_component` accepts `args` as a string
containing a JSON object. jsonlite parses that string as data.
`genui_dispatch()` then validates the result against the types declared by the
component, including scalar types, array types, and enum values. These are the
same checks used for creation, but they happen in dispatch rather than at the
provider.

The argument name `id` is reserved. `parent_id` is also reserved and is added
automatically when a catalog contains a container.

## Trace and replay

Every successful call adds `list(op, id, component, args)` to an ordered trace.
Trace entries contain only values that can be encoded as JSON. They do not
contain environments or values from embedded Shiny inputs.

Replay starts with a fresh registry, then passes each trace entry through the
same dispatch and execution code used for model calls.
`genui_replay(trace, catalog, target)` can therefore rebuild the canvas without
an LLM. Because replay uses the same id assignment and ids are never reused,
the rebuilt components have the same ids. Shiny inputs return to their default values.

`genui_trace()` provides reactive access to the trace.

## Asynchronous work and Shiny sessions

- Tool functions run inside promise chains, where the current reactive domain
  is not reliable. Each function closes over its `session` and passes it
  explicitly to `insertUI()` and `removeUI()`. Component servers run inside
  `withReactiveDomain(session, ...)` so that `moduleServer()` binds to the
  correct session.
- The streaming loop uses `shiny::ExtendedTask` with `stream_async()` and
  `chat_append()`, so work in one session does not block other sessions.
  `ellmer::stream_controller()` supports the cancel button.
- `data` is a reactive passed to component servers. Code that runs during
  dispatch, such as `check()`, receives the current isolated value. This keeps
  the core independent of Shiny. Replay uses the same approach.
- `genui_server(id, ...)` is a module. When `chat_id` is supplied, it refers to
  the session that called the module because the app places `chat_ui()` next
  to `genui_canvas()`. With `chat_id = NULL`, the app developer can provide a
  different chat loop. The registered tools still use the correct session
  because they close over it.
- Every Shiny session must create its own ellmer `Chat`. Sharing a `Chat`
  between sessions would mix conversation history and tool functions from
  different users.

## Confirmed scope

- The model can only emit tool calls. A restricted R language is a possible
  milestone 5 feature, not part of version 0.1.
- Components appear on a canvas next to the chat. Placing components inside
  chat messages is a possible milestone 5 feature.
- Version 0.1 supports interactive inputs inside components. Reactivity
  between components is not supported, though the registry keeps the hook
  described above.
- The trace never records values from embedded inputs. Replay restores their
  defaults.
- ellmer provides support for multiple model providers. Examples use
  `chat_anthropic()` by default.

## Open questions

- If catalogs grow, should each component get its own update tool, such as
  `update_<name>`? This would let the provider validate the full update schema
  but would add one tool for every component. Version 0.1 uses one
  `update_component` tool and validates its arguments in dispatch.
- `modifyList()` drops a key when its JSON value is `null`. This currently
  resets that argument to its default. Is that the behavior we want to
  promise?
- Version 0.1 uses a responsive CSS grid and allows each component to suggest
  a `width`. A later version might let the model choose column spans or use a
  more capable layout system.
- The design assumes one stream in progress for each session. shinychat
  prevents another input in normal use, but the package does not prevent an
  app developer from starting two streams whose tool calls interleave.
