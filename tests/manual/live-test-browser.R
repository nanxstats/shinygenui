# Live browser test: drives the real app (wire_chat streaming loop) in
# headless Chrome via shinytest2. Validates the greeting, the ExtendedTask +
# stream_async + chat_append path, progressive insertUI with dependency
# hoisting (plots actually render), and the embedded slider re-rendering
# with zero chat traffic. Needs Google Chrome.
# Run from the package root: Rscript tests/manual/live-test-browser.R

stopifnot(file.exists("DESCRIPTION"))
Sys.setenv(NOT_CRAN = "true")

pass <- function(ok, label) {
  cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "PASS" else "FAIL", label))
  if (!isTRUE(ok)) assign("failures", get("failures", globalenv()) + 1L, globalenv())
  invisible(ok)
}
failures <- 0L

app <- shinytest2::AppDriver$new(
  "tests/manual/live-app",
  name = "live-browser",
  load_timeout = 60000,
  timeout = 30000,
  view = FALSE
)

send <- function(msg) {
  cat("\n=== USER:", msg, "\n")
  app$run_js(sprintf(
    'Shiny.setInputValue("chat_user_input", %s, {priority: "event"})',
    jsonlite::toJSON(msg, auto_unbox = TRUE)
  ))
}
# shinychat renders messages in div.shiny-chat-messages (a class) inside
# <shiny-chat-container id="chat">.
chat_text <- function() {
  app$get_js('document.querySelector("#chat .shiny-chat-messages")?.textContent ?? ""')
}
shell_count <- function() {
  app$get_js('document.querySelectorAll("#canvas-canvas .genui-shell").length')
}

# Greeting arrives through wire_chat's one-shot observer (no LLM call).
app$wait_for_js('(document.querySelector("#chat .shiny-chat-messages")?.textContent ?? "").includes("mtcars")', timeout = 30000)
pass(TRUE, "greeting rendered in the chat")

# Turn 1: two components; they appear while/before the reply lands.
send("Show mpg vs. hp, and a value box with the average mpg.")
app$wait_for_js('document.querySelectorAll("#canvas-canvas .genui-shell").length >= 2', timeout = 240000)
pass(shell_count() >= 2, "two component shells inserted progressively")

app$wait_for_js('!!document.querySelector("#canvas-canvas .shiny-plot-output img")', timeout = 60000)
pass(TRUE, "scatter plot rendered a real image (deps hoisted)")

box_text <- app$get_js('document.querySelector("#canvas-canvas .bslib-value-box")?.textContent ?? ""')
pass(grepl("20", box_text), "value box shows the computed average mpg (~20.09)")

app$wait_for_js('(document.querySelector("#chat .shiny-chat-messages")?.textContent ?? "").length > 60', timeout = 60000)
pass(TRUE, "assistant reply streamed into the chat")

# Turn 2: interactive histogram.
send("Add a histogram of hp.")
app$wait_for_js('!!document.querySelector("#canvas-canvas .js-range-slider")', timeout = 240000)
pass(TRUE, "histogram with embedded bins slider inserted")

slider_id <- app$get_js(
  'document.querySelector("#canvas-canvas input.js-range-slider").id'
)
cat("slider input id:", slider_id, "\n")
pass(
  grepl("^canvas-c[0-9]+-bins$", slider_id),
  "slider id is namespaced under the instance module"
)

hist_img_src <- function() {
  app$get_js(sprintf(
    'document.getElementById(%s).closest(".card").querySelector(".shiny-plot-output img")?.src.length ?? 0',
    jsonlite::toJSON(slider_id, auto_unbox = TRUE)
  ))
}
app$wait_for_js(sprintf(
  '(document.getElementById(%s).closest(".card").querySelector(".shiny-plot-output img")?.src.length ?? 0) > 0',
  jsonlite::toJSON(slider_id, auto_unbox = TRUE)
), timeout = 60000)
src_before <- hist_img_src()

# The histogram shell appears while the model is still streaming narration
# (progressive rendering); wait for the chat to go quiet before measuring,
# so stream tail-end isn't mistaken for slider-triggered traffic.
chat_before <- nchar(chat_text())
repeat {
  Sys.sleep(3)
  now <- nchar(chat_text())
  if (now == chat_before) break
  chat_before <- now
}

# Drag the slider: plot must re-render with NO chat/LLM traffic.
inputs <- list(9L)
names(inputs) <- slider_id
do.call(app$set_inputs, c(inputs, list(timeout_ = 15000)))

app$wait_for_js(sprintf(
  '(document.getElementById(%s).closest(".card").querySelector(".shiny-plot-output img")?.src.length ?? 0) !== %s',
  jsonlite::toJSON(slider_id, auto_unbox = TRUE),
  src_before
), timeout = 30000)
pass(TRUE, "slider drag re-rendered the histogram at Shiny speed")
Sys.sleep(2)
pass(
  nchar(chat_text()) == chat_before,
  "no chat/LLM traffic during slider interaction"
)

screenshot <- "tests/manual/live-app-final.png"
unlink(screenshot)
app$get_screenshot(screenshot)
cat("screenshot saved to", screenshot, "\n")

app$stop()
cat(sprintf("\n== browser live test: %d failure(s)\n", failures))
quit(status = if (failures > 0) 1L else 0L)
