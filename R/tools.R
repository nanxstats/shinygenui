# Compile a catalog into ellmer tools, plus the built-in lifecycle tools.
#
# Each component becomes one ellmer::tool() whose generated function has one
# formal per declared argument (ellmer requires formals to match the
# declared arguments). All formals default to NULL so omitted optional
# arguments simply drop out before dispatch. The tool implementations only
# ever forward plain data into engine$handle(); nothing the model sends is
# ever evaluated as code.
compile_tools <- function(catalog, engine) {
  with_parent <- catalog_has_containers(catalog)
  tools <- lapply(names(catalog), function(name) {
    compile_component_tool(catalog[[name]], engine, with_parent = with_parent)
  })
  c(tools, builtin_tools(engine))
}

compile_component_tool <- function(component, engine, with_parent = FALSE) {
  arguments <- component$args
  if (with_parent) {
    arguments$parent_id <- ellmer::type_string(
      "Optional id of an existing container instance to place this component into. Omit to place it directly on the canvas.",
      required = FALSE
    )
  }

  handler <- function(args) {
    engine$handle(genui_call(component$name, args))
  }

  ellmer::tool(
    make_tool_fn(names(arguments), handler),
    name = component$name,
    description = component$description,
    arguments = arguments,
    annotations = ellmer::tool_annotations(
      title = paste("Render", component$name)
    )
  )
}

# A function whose formals are exactly `arg_names` (all defaulting to NULL),
# forwarding the provided arguments to `.genui_handler`. The dotted handler
# name cannot collide with component argument names, which must start with a
# letter.
make_tool_fn <- function(arg_names, .genui_handler) {
  force(.genui_handler)
  rlang::new_function(
    rlang::pairlist2(!!!rlang::rep_named(arg_names, list(NULL))),
    quote({
      nms <- names(formals(sys.function())) %||% character()
      .genui_handler(drop_nulls(mget(nms, envir = environment())))
    })
  )
}

builtin_tools <- function(engine) {
  list(
    ellmer::tool(
      function(id = NULL, args = NULL) {
        engine$handle(genui_call(
          "update_component",
          drop_nulls(list(id = id, args = args))
        ))
      },
      name = "update_component",
      description = paste(
        "Update an existing component instance in place, keeping its position on the canvas.",
        "Use this instead of creating a new component whenever the user refines a view that already exists.",
        "Pass only the arguments that change; all other arguments keep their current values."
      ),
      arguments = list(
        id = ellmer::type_string(
          "The instance id to update, as returned when it was created (for example \"c1\")."
        ),
        args = ellmer::type_string(
          paste(
            "A JSON object string mapping argument names to their new values, for example {\"x\": \"hp\"}.",
            "Include only the arguments to change.",
            "Set an optional argument to null to reset it to its default."
          )
        )
      ),
      annotations = ellmer::tool_annotations(title = "Update component")
    ),
    ellmer::tool(
      function(id = NULL) {
        engine$handle(genui_call(
          "remove_component",
          drop_nulls(list(id = id))
        ))
      },
      name = "remove_component",
      description = paste(
        "Remove a component instance from the canvas.",
        "Removing a container also removes the components inside it."
      ),
      arguments = list(
        id = ellmer::type_string(
          "The instance id to remove, as returned when it was created (for example \"c1\")."
        )
      ),
      annotations = ellmer::tool_annotations(title = "Remove component")
    ),
    ellmer::tool(
      function() {
        engine$handle(genui_call("clear_canvas"))
      },
      name = "clear_canvas",
      description = paste(
        "Remove every component from the canvas.",
        "Use only when the user asks to start over or the whole view is being replaced."
      ),
      arguments = list(),
      annotations = ellmer::tool_annotations(title = "Clear canvas")
    ),
    ellmer::tool(
      function() {
        engine$canvas_state()
      },
      name = "get_canvas_state",
      description = paste(
        "Read the current canvas: every component instance with its id,",
        "arguments, and the live values of its embedded inputs (which the",
        "user may have changed since you created it).",
        "Use it when you are unsure what is on the canvas or what the user",
        "adjusted. It changes nothing."
      ),
      arguments = list(),
      annotations = ellmer::tool_annotations(
        title = "Read canvas state",
        read_only_hint = TRUE
      )
    )
  )
}
