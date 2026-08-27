# Container component: a titled row of cards

A container the model can place other components into: create the row,
then create children with `parent_id` set to the row's instance id.
Children lay out in a responsive grid inside the row's card. Removing
the row removes its children. Add it to your
[`genui_catalog()`](https://nanx.me/shinygenui/reference/genui_catalog.md)
alongside
[`genui_components_bslib()`](https://nanx.me/shinygenui/reference/genui_components_bslib.md)
(or your own components) to let the model group related views.

## Usage

``` r
genui_card_row()
```

## Value

A
[`genui_component()`](https://nanx.me/shinygenui/reference/genui_component.md)
object with `container = TRUE`.

## Examples

``` r
catalog <- genui_catalog(
  genui_card_row(),
  genui_component(
    name = "note_card",
    description = "A card showing a short note.",
    args = list(text = "The note text."),
    ui = function(id, args) htmltools::p(args$text)
  )
)
```
