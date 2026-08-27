# Session-scoped instance registry.
#
# Records the canvas state as plain data: one entry per live instance
# (component name, current args, parent id) plus the handles the Shiny
# executor hands back after rendering (module return value, observers to
# destroy, public reactives). Also owns the id counter and the ordered
# trace. All DOM work lives in the executor; the registry only applies
# `genui_plan` objects produced by `genui_dispatch()`, which makes it fully
# testable without Shiny.
#
# Ids are never reused: the counter only moves forward, even after removes
# and clears, so the model can never accidentally address a new instance
# with a stale id.
GenuiRegistry <- R6::R6Class(
  "GenuiRegistry",
  public = list(
    apply = function(plan) {
      if (!inherits(plan, "genui_plan")) {
        genui_abort("{.arg plan} must be a {.cls genui_plan} from {.fn genui_dispatch}.")
      }
      switch(
        plan$action,
        create = private$apply_create(plan),
        update = private$apply_update(plan),
        remove = private$apply_remove(plan),
        clear = private$apply_clear(plan),
        genui_abort("Unknown plan action {.val {plan$action}}.")
      )
      private$notify()
      invisible(plan$id %||% NULL)
    },

    # Store the component server's return value for an instance: collect
    # destroyable observers, and keep a `reactives` element as the public
    # reactives hook for future cross-component wiring.
    set_handles = function(id, value) {
      instance <- private$get_instance(id)
      instance$handles <- value
      instance$observers <- collect_observers(value)
      if (is.list(value) && !is.null(value$reactives)) {
        instance$reactives <- value$reactives
      }
      private$instances[[id]] <- instance
      invisible(self)
    },

    destroy_handles = function(id) {
      instance <- private$instances[[id]]
      if (is.null(instance)) {
        return(invisible(self))
      }
      for (observer in instance$observers) {
        try(observer$destroy(), silent = TRUE)
      }
      instance$observers <- list()
      instance$handles <- NULL
      instance$reactives <- NULL
      private$instances[[id]] <- instance
      invisible(self)
    },

    snapshot = function() {
      list(
        instances = lapply(private$instances, function(x) {
          list(component = x$component, args = x$args, parent_id = x$parent_id)
        }),
        next_id = private$counter + 1L
      )
    },

    trace = function() private$trace_log,

    ids = function() names(private$instances) %||% character(),

    has = function(id) !is.null(private$instances[[id]]),

    get = function(id) private$get_instance(id),

    reactives = function(id) private$get_instance(id)$reactives,

    size = function() length(private$instances),

    # Called with no arguments after every applied plan; the Shiny layer
    # uses it to bump reactive views of the trace and instance list.
    set_on_change = function(fn) {
      stopifnot(is.null(fn) || is.function(fn))
      private$on_change <- fn
      invisible(self)
    }
  ),
  private = list(
    instances = list(),
    counter = 0L,
    trace_log = list(),
    on_change = NULL,

    get_instance = function(id) {
      instance <- private$instances[[id]]
      if (is.null(instance)) {
        genui_abort("No instance {.val {id}} in the registry.")
      }
      instance
    },

    apply_create = function(plan) {
      if (!is.null(private$instances[[plan$id]])) {
        genui_abort("Instance id {.val {plan$id}} already exists; stale plan?")
      }
      private$instances[[plan$id]] <- list(
        component = plan$component,
        args = plan$args,
        parent_id = plan$parent_id,
        handles = NULL,
        observers = list(),
        reactives = NULL
      )
      nums <- instance_id_numbers(plan$id)
      if (length(nums) == 1) {
        private$counter <- max(private$counter, nums)
      }
      private$record(drop_nulls(list(
        op = "create",
        id = plan$id,
        component = plan$component,
        args = plan$args,
        parent_id = plan$parent_id
      )))
    },

    apply_update = function(plan) {
      instance <- private$get_instance(plan$id)
      self$destroy_handles(plan$id)
      instance <- private$instances[[plan$id]]
      instance$args <- plan$args
      private$instances[[plan$id]] <- instance
      private$record(list(op = "update", id = plan$id, args = plan$delta))
    },

    apply_remove = function(plan) {
      private$get_instance(plan$id)
      for (id in plan$ids) {
        self$destroy_handles(id)
        private$instances[[id]] <- NULL
      }
      private$record(list(op = "remove", id = plan$id))
    },

    apply_clear = function(plan) {
      for (id in plan$ids) {
        self$destroy_handles(id)
      }
      private$instances <- list()
      private$record(list(op = "clear"))
    },

    record = function(entry) {
      private$trace_log[[length(private$trace_log) + 1L]] <- entry
    },

    notify = function() {
      if (!is.null(private$on_change)) {
        private$on_change()
      }
    }
  )
)

is_observer_like <- function(x) {
  if (inherits(x, "Observer")) {
    return(TRUE)
  }
  is.environment(x) && is.function(tryCatch(x$destroy, error = function(e) NULL))
}

# Find destroyable observers in a component server's return value: the value
# itself, or elements nested inside plain (unclassed) lists.
collect_observers <- function(x) {
  if (is.null(x)) {
    return(list())
  }
  if (is_observer_like(x)) {
    return(list(x))
  }
  if (is.list(x) && !is.object(x)) {
    found <- lapply(x, collect_observers)
    return(do.call(c, found) %||% list())
  }
  list()
}
