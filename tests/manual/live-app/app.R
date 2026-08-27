# App driven by live-test-browser.R: example 01 wired to the live-test model.
# shinytest2 runs this with the app directory as the working directory, so
# the package root is three levels up.
readRenviron("../../../.env")
pkgload::load_all("../../..", quiet = TRUE)

library(shiny)
library(bslib)

data_context <- paste(
  "The data is R's built-in mtcars dataset: 32 cars (1974 Motor Trend).",
  "Columns: mpg, cyl, disp, hp, drat, wt, qsec, vs, am, gear, carb."
)

ui <- page_sidebar(
  title = "mtcars explorer",
  sidebar = sidebar(
    width = 380,
    open = "always",
    shinychat::chat_ui("chat", height = "100%", fill = TRUE)
  ),
  genui_canvas("canvas", placeholder = "Ask a question to build this view.")
)

server <- function(input, output, session) {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))
  chat <- ellmer::chat_openai(
    model = Sys.getenv("SHINYGENUI_LIVE_MODEL", "gpt-5.6-sol"),
    params = ellmer::params(reasoning_effort = "medium"),
    echo = "none"
  )
  genui_server(
    "canvas",
    catalog = catalog,
    chat = chat,
    data = reactive(mtcars),
    chat_id = "chat",
    greeting = "Hi! Ask me about the mtcars data.",
    system_prompt = genui_prompt(catalog, context = data_context)
  )
}

shinyApp(ui, server)
