#' Collect components into a catalog
#'
#' A catalog is the finite set of components the model is allowed to render.
#' Each component compiles to one [ellmer::tool()]; the built-in lifecycle
#' tools (`update_component`, `remove_component`, `clear_canvas`) are
#' registered alongside it by [genui_server()].
#'
#' @param ... [genui_component()] objects, or lists of them (so component
#'   packs such as [genui_components_bslib()] can be passed directly).
#'
#' @return A `genui_catalog` object: a named list of components, keyed by
#'   component name.
#' @export
#' @examples
#' note <- genui_component(
#'   name = "note_card",
#'   description = "A card showing a short note.",
#'   args = list(text = "The note text."),
#'   ui = function(id, args) htmltools::p(args$text)
#' )
#' catalog <- genui_catalog(note)
#' names(catalog)
genui_catalog <- function(...) {
  components <- collect_components(list(...))
  if (length(components) == 0) {
    genui_abort("A catalog needs at least one {.fn genui_component}.")
  }

  nms <- vapply(components, function(x) x$name, character(1))
  dup <- unique(nms[duplicated(nms)])
  if (length(dup) > 0) {
    genui_abort("Component name{?s} {.val {dup}} {?is/are} duplicated; catalog names must be unique.")
  }

  names(components) <- nms
  structure(components, class = "genui_catalog")
}

collect_components <- function(x, call = rlang::caller_env()) {
  out <- list()
  for (el in x) {
    if (inherits(el, "genui_component")) {
      out <- c(out, list(el))
    } else if (is.list(el) && !is.object(el)) {
      out <- c(out, collect_components(el, call = call))
    } else {
      genui_abort(
        "Catalog entries must be {.fn genui_component} objects, or lists of them.",
        call = call
      )
    }
  }
  out
}

catalog_get <- function(catalog, name) {
  if (name %in% names(catalog)) catalog[[name]] else NULL
}

catalog_has_containers <- function(catalog) {
  any(vapply(catalog, function(x) isTRUE(x$container), logical(1)))
}

check_catalog <- function(catalog, call = rlang::caller_env()) {
  if (!inherits(catalog, "genui_catalog")) {
    genui_abort(
      "{.arg catalog} must be a {.cls genui_catalog} object created by {.fn genui_catalog}.",
      call = call
    )
  }
  invisible(catalog)
}

#' @export
print.genui_catalog <- function(x, ...) {
  cli::cli_text("<genui_catalog> with {length(x)} component{?s}")
  for (component in x) {
    marker <- if (isTRUE(component$container)) " [container]" else ""
    cli::cli_text("  {.val {component$name}}{marker}: {component$description}")
  }
  invisible(x)
}
