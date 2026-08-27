#' Assemble the system prompt from a catalog
#'
#' Renders the packaged whisker template (`inst/prompts/system.md`) with the
#' catalog's components and an optional developer-supplied context string.
#' The result instructs the model to narrate briefly in chat while placing
#' visuals through tools, to reuse `update_component` when the user refines
#' an existing view, and to prefer few, dense components.
#'
#' @param catalog A [genui_catalog()].
#' @param context Optional string appended as an "App context" section:
#'   the data schema, a few sample rows, a business glossary; whatever the
#'   model needs to ground its answers. Raw data is never included unless
#'   you put it here yourself.
#' @param template Optional path to an alternative whisker template, or a
#'   template string. It receives `components` (each with `name`,
#'   `description`, `container`, and formatted `args` lines),
#'   `has_containers`, and `context`.
#'
#' @return A string: the assembled system prompt.
#' @export
#' @examples
#' catalog <- genui_catalog(
#'   genui_component(
#'     name = "note_card",
#'     description = "A card showing a short note.",
#'     args = list(text = "The note text."),
#'     ui = function(id, args) htmltools::p(args$text)
#'   )
#' )
#' cat(genui_prompt(catalog, context = "The data is mtcars."))
genui_prompt <- function(catalog, context = NULL, template = NULL) {
  check_catalog(catalog)
  if (!is.null(context) && !is_string(context)) {
    genui_abort("{.arg context} must be a single string or `NULL`.")
  }

  template <- template %||%
    system.file("prompts", "system.md", package = "shinygenui", mustWork = TRUE)
  if (!is_string(template)) {
    genui_abort("{.arg template} must be a template string or a file path.")
  }
  if (!grepl("\n", template, fixed = TRUE) && file.exists(template)) {
    template <- paste(readLines(template, warn = FALSE), collapse = "\n")
  }

  components <- lapply(unname(as.list(catalog)), function(component) {
    list(
      name = component$name,
      description = component$description,
      container = isTRUE(component$container),
      args = lapply(names(component$args), function(nm) {
        list(line = describe_arg(nm, component$args[[nm]]))
      })
    )
  })

  whisker::whisker.render(
    template,
    data = list(
      components = components,
      has_containers = catalog_has_containers(catalog),
      context = if (!is.null(context) && nzchar(context)) context
    )
  )
}

describe_arg <- function(name, type) {
  required <- isTRUE(attr(type, "required", exact = TRUE))
  description <- attr(type, "description", exact = TRUE)
  sprintf(
    "`%s` (%s%s)%s",
    name,
    type_label(type),
    if (required) "" else "; optional",
    if (!is.null(description) && nzchar(description)) paste0(": ", description) else ""
  )
}

type_label <- function(type) {
  if (inherits(type, "ellmer::TypeEnum")) {
    values <- attr(type, "values", exact = TRUE)
    paste0("one of: ", paste(values, collapse = ", "))
  } else if (inherits(type, "ellmer::TypeBasic")) {
    attr(type, "type", exact = TRUE)
  } else if (inherits(type, "ellmer::TypeArray")) {
    paste0("array of ", type_label(attr(type, "items", exact = TRUE)))
  } else if (inherits(type, "ellmer::TypeObject")) {
    "object"
  } else {
    "value"
  }
}
