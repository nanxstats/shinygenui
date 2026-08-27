#' Canvas container for generated components
#'
#' Place this anywhere in your UI, typically as the main content next to a
#' [shinychat::chat_ui()] sidebar. Components emitted by the model are
#' inserted into it progressively as tool calls complete. Pair it with a
#' [genui_server()] call using the same `id`.
#'
#' @param id Module id, matching the `id` passed to [genui_server()].
#' @param ... Attributes and initial children added to the canvas `<div>`.
#' @param placeholder Text shown while the canvas is empty.
#'
#' @return An [htmltools::tag()] object.
#' @export
#' @examples
#' genui_canvas("canvas")
genui_canvas <- function(id, ..., placeholder = "Components will appear here.") {
  ns <- shiny::NS(id)
  htmltools::div(
    id = ns("canvas"),
    class = "genui-canvas",
    `data-placeholder` = placeholder,
    genui_dependency(),
    ...
  )
}

genui_dependency <- function() {
  htmltools::htmlDependency(
    name = "shinygenui",
    version = as.character(utils::packageVersion("shinygenui")),
    package = "shinygenui",
    src = "assets",
    stylesheet = "genui.css"
  )
}
