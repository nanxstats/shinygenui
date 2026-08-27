# Manual live tests

Opt-in acceptance tests that talk to a real LLM. testthat never runs these;
run them yourself from the **package root**:

```sh
Rscript tests/manual/live-test-grounded.R   # acceptance scenarios 1-3, 5 + get_canvas_state
Rscript tests/manual/live-test-errors.R     # scenario 4: tool-error recovery + clear_canvas
Rscript tests/manual/live-test-browser.R    # headless-Chrome run of the real streaming app
```

Requirements:

- A `.env` file at the package root containing `OPENAI_API_KEY=...`
  (gitignored and Rbuildignored; loaded via `readRenviron(".env")`).
- The browser test additionally needs Google Chrome and the shinytest2 +
  chromote packages; it sets `NOT_CRAN` itself and writes
  `live-app-final.png` (gitignored) next to the scripts.

The model defaults to `gpt-5.6-sol` with medium reasoning effort; override
with the `SHINYGENUI_LIVE_MODEL` environment variable. Each script prints
`[PASS]`/`[FAIL]` lines and exits nonzero on any failure.

Timing note for assertions: components land on the canvas *while* the model
is still streaming narration (progressive rendering). Any check that the
chat is quiet must first wait for the in-flight stream to finish.
