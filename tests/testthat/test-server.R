# genui_server integration under shiny::testServer, with a real ellmer Chat
# object that never talks to the network (tools are invoked directly).

local_chat <- function() {
  ellmer::chat_openai(model = "gpt-5", credentials = function() list(api_key = "not-a-real-key"))
}

test_that("genui_server registers tools and installs the system prompt", {
  chat <- local_chat()
  shiny::testServer(
    genui_server,
    args = list(
      id = "genui",
      catalog = test_catalog(),
      chat = chat,
      data = function() NULL
    ),
    {
      expect_setequal(
        names(chat$get_tools()),
        c(
          "value_box", "scatter_plot", "data_table", "card_row",
          "update_component", "remove_component", "clear_canvas"
        )
      )
      expect_match(chat$get_system_prompt(), "### value_box")
    }
  )
})

test_that("a custom system prompt wins", {
  chat <- local_chat()
  shiny::testServer(
    genui_server,
    args = list(
      id = "genui",
      catalog = test_catalog(),
      chat = chat,
      system_prompt = "You only speak in haiku."
    ),
    {
      expect_identical(chat$get_system_prompt(), "You only speak in haiku.")
    }
  )
})

test_that("registered tools drive the canvas and the returned reactives", {
  chat <- local_chat()
  shiny::testServer(
    genui_server,
    args = list(
      id = "genui",
      catalog = test_catalog(),
      chat = chat,
      data = function() NULL
    ),
    {
      tools <- chat$get_tools()
      result <- suppressWarnings(
        tools$value_box(title = "Average MPG", column = "mpg")
      )
      expect_true(inherits(result, "ellmer::ContentToolResult"))

      handles <- session$returned
      expect_length(handles$trace(), 1)
      expect_named(handles$instances(), "c1")

      suppressWarnings(tools$update_component(id = "c1", args = '{"title": "MPG"}'))
      expect_length(handles$trace(), 2)
      expect_identical(handles$instances()$c1$args$title, "MPG")

      suppressWarnings(tools$remove_component(id = "c1"))
      expect_length(handles$instances(), 0)

      # a failed call reaches the model as a tool error, not a crash: the
      # compiled tool signals, ellmer's invoker catches
      expect_error(
        tools$value_box(title = "A", column = "nope"),
        class = "genui_dispatch_error"
      )
      expect_length(handles$trace(), 3)
    }
  )
})

test_that("genui_server validates its inputs", {
  expect_error(
    shiny::testServer(
      genui_server,
      args = list(id = "genui", catalog = test_catalog(), chat = "not a chat"),
      {
      }
    ),
    class = "genui_error"
  )
})
