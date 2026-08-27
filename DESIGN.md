# shinygenui design

Declarative, catalog-constrained generative UI for Shiny. The app developer
defines a finite catalog of components; end users chat with an LLM that
composes, updates, and removes instances of those components on a canvas,
streamed progressively into a plain Shiny app. The R/Shiny analogue of
Vercel's json-render and Google's A2UI, narrowed to one language, one
framework, one deployment story.

## Layers

1. **Pure core** (no Shiny, no LLM): `genui_component()`, `genui_catalog()`,
   `genui_dispatch()`, argument validation against ellmer types. Fully unit
   tested with hand-built fake tool calls.
2. **Session state**: `GenuiRegistry` (R6). Holds instances (id, component
   name, current args, parent id, observer handles, public-reactives hook),
   the id counter, and the ordered trace. State transitions only; no DOM.
3. **Shiny executor**: turns dispatch plans into `insertUI()` / `removeUI()`
   calls and module-server instantiations, always with an explicit `session`.
4. **LLM wiring**: catalog → `ellmer::tool()` compilation, built-in lifecycle
   tools, prompt assembly (whisker template), shinychat streaming loop.

Objects: R6 for stateful classes (`GenuiRegistry`), plain S3 lists for
declarative data (`genui_component`, `genui_catalog`, plans, trace entries),
ellmer's S7 `ContentToolResult` for tool results — mirroring querychat's split.

## Data flow

```
user message ──shinychat──▶ chat$stream_async(stream = "content")  [ExtendedTask]
  ──▶ model streams narrative text ──▶ chat_append() renders it
  ──▶ model emits tool call (schema-validated args, JSON on the wire only)
        ──▶ compiled tool fn: normalize to a genui_call
              ──▶ genui_dispatch(catalog, call, state)  [pure]
                    validates: component exists, ids exist, args well-typed,
                    semantic check() hook passes → returns a *plan*
                    (create/update/remove/clear + resolved id, merged args,
                    target selector) or signals a classed genui error
              ──▶ registry records the transition + appends trace entry
              ──▶ executor: insertUI(immediate = TRUE, session = session),
                    withReactiveDomain(session, component$server(id, args, data))
        ──▶ tool returns ContentToolResult(value = "Created c1 (scatter_plot)",
              extra = display metadata for shinychat's tool display)
  ──▶ model sees the instance id, continues narrating / calling tools
```

Errors anywhere inside the tool fn (dispatch validation, `check()` hook,
rendering) propagate as ordinary R conditions; ellmer's tool invoker catches
them and returns `ContentToolResult(error = ...)` to the model, which
self-corrects in its next turn. The Shiny session never crashes; the worst
case is an ugly dashboard. The model never emits R code and the package never
calls `eval()`/`parse()` on model output — arguments are data, interpreted
only by developer-written component functions.

ellmer invokes tools when the assistant turn that requested them completes,
then loops for a follow-up turn. Because each validated call inserts UI
`immediate = TRUE` from inside the async chain, components pop onto the canvas
mid-conversation while the surrounding `chat_append()` stream is still open —
progressive rendering without any custom transport.

## Instances and lifecycle

Every instance gets a stable id `c1, c2, ...` (counter lives in the registry)
and renders inside a stable shell `div(id = ns("shell-c1"))` appended to the
canvas `div(id = ns("canvas"))`. The component's module id is the instance id,
scoped under the genui module's namespace, so embedded inputs are collision-free
and interaction re-renders at Shiny speed with zero LLM round trips.

- **create**: dispatch assigns the next id; executor inserts the shell into the
  canvas (or a container instance's slot when `parent_id` is given) and runs
  the component's `server(id, args, data)` under the module session.
- **update**: `update_component(id, args)` — dispatch merges the partial args
  over the current args (`modifyList()`), re-validates, and the executor
  destroys the instance's observers, empties the shell (`removeUI` on its
  children), and re-instantiates UI + server with merged args. The shell never
  moves, so position is preserved and there is no flicker. In v0.1 embedded
  input state resets to defaults on update (the module is re-instantiated);
  snapshot/restore of input values across updates is explicitly future work.
- **remove / clear**: destroy observers (children first for containers), then
  `removeUI()` the shell(s).

**Observer teardown contract**: a component `server` function returns its
moduleServer result; any observers included in that returned value (a single
observer or nested in a list) are collected by the registry and `$destroy()`ed
on update/remove. A returned `reactives` element is stored keyed by instance id
— the v0.2 hook for cross-component reactivity (a single blessed filtered-data
channel, not arbitrary pub/sub); nothing reads it in v0.1. Known Shiny
limitation: output render functions cannot be truly unregistered. On update we
reuse the same ids, so re-registration replaces them; on remove, orphaned
outputs stay suspended with no bound DOM element, which is acceptable.

## Tools and schemas

Each catalog entry compiles to an `ellmer::tool()` whose formals are generated
from the declared arg names (ellmer requires formals ↔ arguments to match).
Catalogs may be built per session inside the server function, so arg types can
enumerate live facts (e.g. dataset columns as `type_enum` values) — a
hallucinated column is a schema violation the model must correct. Three
built-ins ride alongside: `update_component`, `remove_component`,
`clear_canvas`. Because ellmer cannot express per-component union schemas,
`update_component` takes `args` as a JSON object *string*; it is parsed with
jsonlite (data, never code) and validated server-side against the component's
declared types (enum membership, scalar/array kinds) — same guardrail, enforced
in dispatch instead of by the provider. Reserved arg names: `parent_id`
(auto-added to every component when the catalog contains containers), `id`.

## Trace and replay

Every validated call appends `list(op, id, component, args)` to an ordered
trace (plain JSON-able lists, no environments). Replay is a fold: fresh
registry, then dispatch + execute each entry through the exact pipeline the
LLM path uses — `genui_replay(trace, catalog, target)` rebuilds the canvas
with no LLM configured. Embedded input state is ephemeral by decision: never
recorded, replay restores defaults. `genui_trace()` exposes the trace as a
reactive read.

## Async and session rules

- Tool fns fire inside promise chains where the ambient reactive domain is
  unreliable: every tool closes over `session` and passes it explicitly to
  `insertUI()`/`removeUI()`; component servers run inside
  `withReactiveDomain(session, ...)` so `moduleServer()` binds correctly.
- The streaming loop is a `shiny::ExtendedTask` (`stream_async` → promise →
  `chat_append`), so other sessions never block; `ellmer::stream_controller()`
  backs the cancel button.
- `data` is a reactive passed to component servers; dispatch-time consumers
  (`check()` hooks, replay) receive its isolated current value, keeping the
  core pure.
- `genui_server(id, ...)` is a module; the optional shinychat wiring
  (`chat_id`) resolves against the *caller's* session, since the developer
  places `chat_ui()` alongside `genui_canvas()` at the call site. With
  `chat_id = NULL` developers run their own loop; registered tools work
  regardless because they close over the right session.
- The `Chat` object must be created per session (document loudly); sharing one
  across sessions would cross-wire tool closures.

## Confirmed scope (maintainer decisions)

- Emission is tool calls only; restricted R DSL is an M5 stretch, not v0.1.
- Layout is chat + canvas; inline-in-chat rendering is an M5 stretch.
- Embedded interactive inputs are v0.1; cross-component reactive wiring is not
  (registry keeps the hook described above).
- Embedded input state is never in the trace; replay restores defaults.
- Provider-agnostic via ellmer; examples default to `chat_anthropic()`.

## Open questions

- Should `update_component` become per-component `update_<name>` tools (full
  provider-side schema enforcement, n more tools) once catalogs grow? v0.1
  ships the single built-in with server-side validation.
- `modifyList()` drops keys on JSON `null` — currently "reset that arg to its
  default"; is that the semantics we want to promise?
- Canvas layout: v0.1 uses a simple responsive CSS grid with an optional
  per-component `width` hint; real layout negotiation (model-chosen spans)
  may deserve a `layout` arg later.
- Concurrency: one in-flight stream per session is assumed; shinychat's input
  gating enforces it in practice, but nothing structural prevents a developer
  from invoking two streams whose tool calls interleave.
