# mtcars explorer: chat + canvas generative UI demo.
#
# The model can only render what the catalog allows: a value box, a markdown
# card, a data table, a scatter plot, and a histogram whose bin-count slider
# is live Shiny input (no LLM round trip). Column arguments are enums
# grounded on mtcars, so hallucinated columns come back as tool errors the
# model corrects itself.
#
# Requires an Anthropic API key in ANTHROPIC_API_KEY. Any ellmer provider
# works: swap ellmer::chat_anthropic() for ellmer::chat_openai(),
# ellmer::chat_ollama(), etc.
#
# Try, in order:
#   1. "Show mpg vs. hp, and a value box with the average mpg."
#   2. "Color the scatter by cylinders and drop the value box."
#   3. "Add a histogram of hp."           (then drag the bins slider)
#   4. "Add a scatter of mpg vs. gear ratio."  (watch it recover)

library(shiny)
library(bslib)
library(shinygenui)

data_context <- paste(
  "The data is R's built-in mtcars dataset: 32 cars from the 1974 Motor",
  "Trend magazine, one row per car model.",
  "Columns: mpg (miles per US gallon), cyl (number of cylinders: 4, 6, 8),",
  "disp (displacement, cubic inches), hp (gross horsepower), drat (rear",
  "axle ratio), wt (weight, 1000 lbs), qsec (quarter mile time, seconds),",
  "vs (engine shape: 0 = V-shaped, 1 = straight), am (transmission: 0 =",
  "automatic, 1 = manual), gear (number of forward gears), carb (number of",
  "carburetors)."
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

  # One Chat per session: create it here, never at the top level.
  chat <- ellmer::chat_anthropic()

  genui_server(
    "canvas",
    catalog = catalog,
    chat = chat,
    data = reactive(mtcars),
    chat_id = "chat",
    greeting = paste(
      "Hi! I can build views of the **mtcars** data for you.",
      "Try: *Show mpg vs. hp, and a value box with the average mpg.*"
    ),
    system_prompt = genui_prompt(catalog, context = data_context)
  )
}

shinyApp(ui, server)
