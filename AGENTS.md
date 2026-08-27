# AGENTS.md

Guidance for coding agents working on {shinygenui}: declarative,
catalog-constrained generative UI for Shiny. Read `DESIGN.md` first; it is
the architecture spec of record and must be updated when the architecture
changes.

## Workflow

- Quality gate: `devtools::document()` + `devtools::check()` must pass with
  **0 errors, 0 warnings, 0 notes** before any milestone or PR is called
  done. R is available locally; run the checks, don't assume.
- Vendored, read-only dependency sources live in `deps-src/` (regenerate
  with `okr sync`; see `deps-src/_manifest.md` for versions). When unsure
  about an ellmer/shinychat/shiny API or internal behavior, read the
  vendored source instead of guessing — pin behavior to what the vendored
  version actually does.
- testthat suites under `tests/testthat/` must never touch the network, an
  LLM, or a real browser. Shiny-side behavior is tested with
  `shiny::testServer` and hand-built `genui_call()` objects.
- Live LLM acceptance tests live in `tests/manual/` (never auto-run; see
  its README). `.env` at the package root holds `OPENAI_API_KEY` — it is
  gitignored and Rbuildignored; load with `readRenviron(".env")`, and never
  commit or print it. The designated live model is `gpt-5.6-sol` with
  `ellmer::params(reasoning_effort = "medium")`.

## Architecture invariants (do not break)

- The model never emits code and the package never calls `eval()`/`parse()`
  on model output. Tool arguments are plain data validated by
  `genui_dispatch()` (pure, no Shiny/LLM) before anything renders.
- Every `insertUI()`/`removeUI()` passes `session = ` explicitly, and
  component servers run under `shiny::withReactiveDomain(session, ...)`:
  tool calls fire inside ellmer's async promise chains where the ambient
  reactive domain is unreliable.
- Instance ids (`c1`, `c2`, ...) are assigned deterministically and never
  reused. Trace entries are plain JSON-able lists; embedded input state is
  intentionally never recorded (replay restores defaults).
- `update_component` re-instantiates the module inside the instance's
  stable shell (same position, same ids); observer handles live in the
  registry and are destroyed on update/remove. Output render functions
  can't be unregistered — replaced on update, left suspended on remove.
- Errors during tool handling must propagate as conditions (never crash the
  session): ellmer converts them to tool errors via `conditionMessage()`,
  which is therefore model-facing text — make it actionable (name the bad
  value, list the valid ones).
- One ellmer `Chat` per Shiny session. Component `description`s and
  `inst/prompts/system.md` are product surface; edit them with care.

## Gotchas learned in this codebase

- cli: a message interpolating two vectors makes `{?s}` fail with
  "Multiple quantities for pluralization" — prefix with
  `{cli::qty(length(x))}`. Wrappers around `cli_abort()` must thread
  `.envir = parent.frame()` (and a `call` argument) or interpolation
  happens in the wrong frame.
- Never let model-supplied text reach the cli/glue interpolator (it may
  contain braces or JSON): `sprintf()` it first, then interpolate the
  result as a single value.
- `R6::R6Class` requires unique names across `public` + `private` +
  `active` combined.
- whisker treats `""` as truthy; pass `NULL` to suppress a template
  section.
- ellmer types are S7: class vectors look like
  `c("ellmer::TypeEnum", "ellmer::Type", "S7_object")`; read properties
  with `attr(x, "values", exact = TRUE)` etc. `ellmer::tool()` requires the
  function's formals to exactly match the declared `arguments` (generate
  formals with `rlang::new_function()` + `rlang::pairlist2()`).
- `chat_openai(api_key = )` is deprecated; use
  `credentials = function() list(api_key = ...)` in tests.
- `shiny::MockShinySession` implements `sendInsertUI`/`sendRemoveUI` as
  *warning* no-ops: full engine paths run fine under `testServer` — wrap
  calls in `suppressWarnings()`.
- shinychat DOM (0.4.x): messages render in `div.shiny-chat-messages`
  inside `<shiny-chat-container id="...">` (class selector, not element);
  user input arrives as `input$<id>_user_input`, cancel as
  `input$<id>_cancel`.
- Progressive rendering timing: components land on the canvas while the
  model is still streaming narration. Any assertion that chat is "quiet"
  must first wait for the in-flight stream to finish.
- shinytest2 refuses to run without `NOT_CRAN=true` (scripts may
  `Sys.setenv` it themselves).
