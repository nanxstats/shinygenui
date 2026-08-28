# AGENTS.md

shinygenui lets a language model build a Shiny interface from a designated
catalog of components. Read `DESIGN.md` first. It is the main architecture
document and must be updated whenever the architecture changes.

## Workflow

- Before calling a milestone or PR complete, run `devtools::document()` and
  `devtools::check()`. The result must have **0 errors, 0 warnings, 0 notes**.
  R is available locally, so do not assume that the checks pass.
- Dependency sources in `deps-src/` are provided for reference and must not be
  edited. Regenerate them with `okr sync`; see `deps-src/_manifest.md` for
  versions. If you are unsure how ellmer, shinychat, or Shiny behaves, read
  the version in `deps-src/` instead of guessing.
- testthat suites under `tests/testthat/` must never touch the network, an
  LLM, or a real browser. Test Shiny behavior with `shiny::testServer` and
  `genui_call()` objects created by hand.
- Live LLM acceptance tests live in `tests/manual/`. Never run them
  automatically; see the README in that directory. The `.env` file at the
  package root contains `OPENAI_API_KEY`. Git and R builds ignore this file.
  Load it with `readRenviron(".env")`, and never commit or print it. The
  designated live model is `gpt-5.6-sol` with
  `ellmer::params(reasoning_effort = "medium")`.

## Architecture invariants (do not break)

- The model never emits code, and the package never calls `eval()` or
  `parse()` on model output. Tool arguments are plain data. The pure
  `genui_dispatch()` function validates them before anything is rendered and
  does not depend on Shiny or an LLM.
- Every call to `insertUI()` or `removeUI()` supplies `session = ` explicitly.
  Component servers run under `shiny::withReactiveDomain(session, ...)`.
  Tools run inside ellmer's asynchronous promise chains, where the current
  reactive domain is not reliable.
- Instance ids (`c1`, `c2`, ...) are assigned deterministically and never
  reused. Trace entries are plain lists that can be encoded as JSON. Values
  from Shiny inputs are deliberately not recorded, so replay restores their
  defaults.
- `update_component` creates the module again inside the same shell, which
  preserves its position and ids. The registry stores observer handles and
  destroys them when a component is updated or removed. Shiny output render
  functions cannot be unregistered. An update replaces them, while a removal
  leaves them suspended.
- Errors while handling tools must propagate as R conditions and must never
  crash the session. ellmer turns each condition into a tool error using
  `conditionMessage()`, so the message is shown to the model. Make it useful:
  name the invalid value and list the valid choices.
- One ellmer `Chat` per Shiny session. Component `description`s and
  `inst/prompts/system.md` are part of the product. Edit them with care.

## Gotchas learned in this codebase

- In cli, a message that interpolates two vectors makes `{?s}` fail with
  "Multiple quantities for pluralization". Prefix the message with
  `{cli::qty(length(x))}`. Wrappers around `cli_abort()` must pass
  `.envir = parent.frame()` and a `call` argument, or interpolation happens
  in the wrong frame.
- Never let text supplied by the model reach the cli or glue interpolator. It
  may contain braces or JSON. Format it with `sprintf()` first, then
  interpolate the result as a single value.
- `R6::R6Class` requires names to be unique across `public`, `private`, and
  `active`.
- whisker treats `""` as truthy; pass `NULL` to suppress a template section.
- ellmer types are S7: class vectors look like
  `c("ellmer::TypeEnum", "ellmer::Type", "S7_object")`. Read properties
  with `attr(x, "values", exact = TRUE)` and related calls. `ellmer::tool()`
  requires the function's formals to exactly match the declared `arguments`.
  Generate formals with `rlang::new_function()` and `rlang::pairlist2()`.
- `chat_openai(api_key = )` is deprecated; use
  `credentials = function() list(api_key = ...)` in tests.
- `shiny::MockShinySession` implements `sendInsertUI`/`sendRemoveUI` as
  functions that warn and do nothing. Full engine paths still run under
  `testServer`; wrap calls in `suppressWarnings()`.
- shinychat DOM (0.4.x): messages render in `div.shiny-chat-messages`
  inside `<shiny-chat-container id="...">` (class selector, not element);
  user input arrives as `input$<id>_user_input`, cancel as
  `input$<id>_cancel`.
- Progressive rendering timing: components land on the canvas while the
  model is still streaming narration. Any assertion that chat is "quiet"
  must first wait for the stream in progress to finish.
- shinytest2 refuses to run without `NOT_CRAN=true` (scripts may
  `Sys.setenv` it themselves).
