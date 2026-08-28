# Layout + trace/replay demo: containers via card_row, and rebuilding the
# canvas from the trace with no LLM in the loop.
#
# The catalog is the bslib starter pack plus the card_row container. Ask the
# model to group things, then press "Replay" to fold the recorded trace onto
# the second canvas: every component comes back (embedded inputs at their
# defaults) without a single model call.
#
# Requires OPENAI_API_KEY, SHINYGENUI_MODEL, and SHINYGENUI_EFFORT. Load them
# from a .env file before running the app; see the package README.
#
# Try:
#   1. "Create a row of KPIs: average mpg, average hp, and max wt."
#      (one card_row, three value boxes created into it via parent_id)
#   2. "Below the row, add a histogram of mpg."
#   3. "Retitle the row to 'Key numbers' and drop the hp box."
#   4. Press "Replay trace onto the mirror canvas".

if (file.exists(".env")) {
  readRenviron(".env")
}
required_env <- c("OPENAI_API_KEY", "SHINYGENUI_MODEL", "SHINYGENUI_EFFORT")
missing_env <- required_env[!nzchar(Sys.getenv(required_env))]
if (length(missing_env) > 0) {
  stop(
    sprintf(
      "Set these variables in .env: %s",
      paste(missing_env, collapse = ", ")
    ),
    call. = FALSE
  )
}

library(shiny)
library(bslib)
library(shinygenui)

ui <- page_sidebar(
  title = "Layout and replay",
  sidebar = sidebar(
    width = 380,
    open = "always",
    shinychat::chat_ui("chat", height = "100%", fill = TRUE)
  ),
  h5("Live canvas"),
  genui_canvas("live", placeholder = "Ask for a row of KPIs to get started."),
  hr(),
  actionButton("replay", "Replay trace onto the mirror canvas", width = "fit-content"),
  h5("Mirror canvas (rebuilt from the trace, no LLM)"),
  genui_canvas("mirror", placeholder = "Press the replay button.")
)

server <- function(input, output, session) {
  catalog <- genui_catalog(
    genui_card_row(),
    genui_components_bslib(data = mtcars)
  )

  chat <- ellmer::chat_openai(
    model = Sys.getenv("SHINYGENUI_MODEL"),
    params = ellmer::params(
      reasoning_effort = Sys.getenv("SHINYGENUI_EFFORT")
    ),
    echo = "none"
  )

  handles <- genui_server(
    "live",
    catalog = catalog,
    chat = chat,
    data = reactive(mtcars),
    chat_id = "chat",
    greeting = paste(
      "I can arrange views of **mtcars** in rows.",
      "Try: *Create a row of KPIs: average mpg, average hp, and max wt.*"
    ),
    system_prompt = genui_prompt(
      catalog,
      context = "The data is R's built-in mtcars dataset (32 cars, 11 numeric columns)."
    )
  )

  observeEvent(input$replay, {
    genui_replay(
      isolate(handles$trace()),
      catalog = catalog,
      target = "mirror",
      data = reactive(mtcars)
    )
  })
}

shinyApp(ui, server)
