# mtcars explorer: chat + canvas generative UI demo.
#
# The model can only render what the catalog allows: a value box, a markdown
# card, a data table, a scatter plot, and a histogram whose bin-count slider
# is live Shiny input (no LLM round trip). Column arguments are enums
# grounded on mtcars, so hallucinated columns come back as tool errors the
# model corrects itself.
#
# Requires OPENAI_API_KEY, SHINYGENUI_MODEL, and SHINYGENUI_EFFORT. Load them
# from a .env file before running the app; see the package README.
#
# Try, in order:
#   1. "Show mpg vs. hp, and a value box with the average mpg."
#   2. "Color the scatter by cylinders and drop the value box."
#   3. "Add a histogram of hp."           (then drag the bins slider)
#   4. "Add a scatter plot of mpg vs. gear ratio."  (watch it recover)

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

example_prompts <- c(
  "Show mpg vs. hp, and a value box with the average mpg.",
  "Color the scatter by cylinders and drop the value box.",
  "Add a histogram of hp.",
  "Add a scatter plot of mpg vs. gear ratio."
)

example_prompt_buttons <- div(
  class = "example-prompts",
  tags$span("Try an example:", class = "example-prompts-label"),
  lapply(seq_along(example_prompts), function(i) {
    actionButton(
      paste0("example_prompt_", i),
      example_prompts[[i]],
      class = "btn-sm btn-outline-secondary"
    )
  })
)

ui <- page_sidebar(
  tags$head(
    tags$style(HTML("
      #chat .shiny-chat-footer {
        grid-row: 2;
        padding: 0 0 0.5rem;
      }

      #chat .shiny-chat-input {
        grid-row: 3;
      }

      #chat .shiny-chat-input textarea {
        --bs-border-radius: var(--bs-border-radius-sm, 0.25rem);
        scrollbar-width: none;
      }

      #chat .shiny-chat-input textarea::-webkit-scrollbar {
        display: none;
      }

      .example-prompts {
        display: flex;
        flex-direction: column;
        align-items: stretch;
        gap: 0.25rem;
        text-align: left;
      }

      .example-prompts-label {
        font-weight: 600;
      }

      .example-prompts .action-button {
        white-space: normal;
        text-align: left;
      }
    "))
  ),
  title = "mtcars explorer",
  sidebar = sidebar(
    width = 380,
    open = "always",
    shinychat::chat_ui(
      "chat",
      height = "100%",
      fill = TRUE,
      footer = example_prompt_buttons
    )
  ),
  genui_canvas("canvas", placeholder = "Ask a question to build this view.")
)

server <- function(input, output, session) {
  catalog <- genui_catalog(genui_components_bslib(data = mtcars))

  for (i in seq_along(example_prompts)) {
    local({
      prompt_id <- paste0("example_prompt_", i)
      prompt <- example_prompts[[i]]

      observeEvent(input[[prompt_id]], {
        shinychat::update_chat_user_input(
          "chat",
          value = prompt,
          focus = TRUE,
          session = session
        )
      })
    })
  }

  # One Chat per session: create it here, never at the top level.
  chat <- ellmer::chat_openai(
    model = Sys.getenv("SHINYGENUI_MODEL"),
    params = ellmer::params(
      reasoning_effort = Sys.getenv("SHINYGENUI_EFFORT")
    ),
    echo = "none"
  )

  genui_server(
    "canvas",
    catalog = catalog,
    chat = chat,
    data = reactive(mtcars),
    chat_id = "chat",
    greeting = paste(
      "Hi! I can build views of the **mtcars** data for you.",
      "Choose an example below, or write your own prompt."
    ),
    system_prompt = genui_prompt(catalog, context = data_context)
  )
}

shinyApp(ui, server)
