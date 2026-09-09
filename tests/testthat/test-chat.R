# Exercise chat_server() with a real Chat whose streaming method is replaced
# before use. No provider, network, or browser is used.
offline_stream_chat <- function(stream_async = function(...) stop("Unexpected model call")) {
  chat <- ellmer::chat_openai(
    model = "not-used",
    credentials = function() list(api_key = "not-used")
  )
  rlang::env_binding_unlock(chat, "stream_async")
  chat$stream_async <- stream_async
  rlang::env_binding_lock(chat, "stream_async")
  chat
}

finish_chat_loop <- function(loop, session) {
  deadline <- proc.time()[["elapsed"]] + 5
  repeat {
    session$flushReact()
    if (loop$status() == "idle") break
    if (proc.time()[["elapsed"]] > deadline) {
      stop("The offline chat task did not finish")
    }
  }
  invisible(NULL)
}

test_that("chat input forwards text and attachment content in the caller's namespace", {
  for (user_input in list(
    "Show mpg vs hp",
    list("Show mpg vs hp"),
    list("Describe this image", ellmer::content_image_url("https://example.invalid/image.png")),
    list(ellmer::ContentText("Attachment-only content"))
  )) {
    calls <- list()
    messages <- list()
    chat <- offline_stream_chat(function(..., stream, controller) {
      calls[[length(calls) + 1L]] <<- list(
        input = rlang::list2(...), stream = stream, controller = controller
      )
      "Offline reply"
    })

    shiny::testServer(function(input, output, session) {
      session$sendCustomMessage <- function(type, message) {
        messages[[length(messages) + 1L]] <<- list(type = type, message = message)
      }
      loop <- shiny::moduleServer("outer", function(input, output, session) {
        parent_session <- session
        shiny::moduleServer("canvas", function(input, output, session) {
          shinygenui:::wire_chat(chat, "chat", greeting = NULL, session = parent_session)
        })
      })
    }, {
      session$setInputs(`outer-chat_user_input` = user_input)
      finish_chat_loop(loop, session)
      expect_length(calls, 1)
      expected_input <- if (is.list(user_input)) user_input else list(user_input)
      expect_identical(calls[[1]]$input, expected_input)
      expect_identical(calls[[1]]$stream, "content")
      expect_match(jsonlite::toJSON(messages, auto_unbox = TRUE), "Offline reply")
      expect_true(all(vapply(messages, function(x) identical(x$message$id, "outer-chat"), logical(1))))
      expect_null(loop$last_error())
      expect_null(loop$history$conversation_id())
      expect_false(loop$history$save())
    })
  }
})

test_that("the greeting uses shinychat's display-only welcome message", {
  messages <- list()
  chat <- offline_stream_chat()

  shiny::testServer(function(input, output, session) {
    session$sendCustomMessage <- function(type, message) {
      messages[[length(messages) + 1L]] <<- message
    }
    shinygenui:::wire_chat(chat, "chat", c("Hello", "mtcars"), session)
  }, {
    session$flushReact()
    expect_match(jsonlite::toJSON(messages, auto_unbox = TRUE), "Hello")
    expect_match(jsonlite::toJSON(messages, auto_unbox = TRUE), "mtcars")
    greetings <- Filter(function(x) identical(x$action$type, "greeting"), messages)
    expect_length(greetings, 1)
    expect_identical(greetings[[1]]$action$content, "Hello\nmtcars")
    expect_false(greetings[[1]]$action$options$persistent)
    expect_length(chat$get_turns(), 0)
    first_messages <- messages
    session$flushReact()
    expect_identical(messages, first_messages)
  })
})

test_that("cancel input reaches the stream controller", {
  cancelled <- FALSE
  controller <- list(cancel = function() cancelled <<- TRUE)
  local_mocked_bindings(
    stream_controller = function() controller,
    .package = "ellmer"
  )

  chat <- offline_stream_chat()
  messages <- list()
  shiny::testServer(function(input, output, session) {
    session$sendCustomMessage <- function(type, message) {
      messages[[length(messages) + 1L]] <<- message
    }
    shinygenui:::wire_chat(chat, "chat", greeting = NULL, session = session)
  }, {
    session$flushReact()
    cancel_config <- Filter(function(x) identical(x$action$type, "update_cancel"), messages)
    expect_length(cancel_config, 1)
    expect_true(cancel_config[[1]]$action$enable_cancel)
    expect_false(cancelled)
    session$setInputs(chat_cancel = 1)
    expect_true(cancelled)
  })
})

test_that("genui_server binds the native chat to the caller's session", {
  registrations <- list()
  local_mocked_bindings(
    chat_server = function(id, client, greeting, history, session) {
      registrations[[length(registrations) + 1L]] <<- list(
        id = id,
        client = client,
        greeting = greeting,
        history = history,
        namespace = session$ns(NULL),
        domain = shiny::getDefaultReactiveDomain()$ns(NULL)
      )
      invisible(NULL)
    },
    .package = "shinychat"
  )
  chat <- offline_stream_chat()

  shiny::testServer(function(input, output, session) {
    shiny::moduleServer("outer", function(input, output, session) {
      genui_server("canvas", test_catalog(), chat, chat_id = "chat", greeting = "Hello")
    })
  }, {
    expect_length(registrations, 1)
    registration <- registrations[[1]]
    expect_identical(registration$id, "chat")
    expect_identical(registration$client, chat)
    expect_identical(registration$greeting, "Hello")
    expect_false(registration$history)
    expect_identical(registration$namespace, "outer")
    expect_identical(registration$domain, "outer")
    expect_true("value_box" %in% names(chat$get_tools()))
  })
})
