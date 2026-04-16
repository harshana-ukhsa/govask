# Skill: Shiny UI Components for the RAG Interface

## When to use this skill

Load this skill when asked to:
- Scaffold or extend the Shiny application (`app.R`)
- Build any new UI component (input, output panel, sidebar filter)
- Write server-side reactive logic for RAG interactions
- Style the answer or source citation panels
- Add loading states, error handling, or notifications

---

## Full app scaffold

This is the complete starting template. Copilot should fill in the `server` function when asked to wire up the backend.

```r
library(shiny)
library(bslib)
library(DT)
library(shinycssloaders)

# ── Constants ─────────────────────────────────────────────────────────────────
STORE_PATH <- "data/rag_store.duckdb"
TOP_K      <- 5L

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  theme = bslib::bs_theme(bootswatch = "flatly"),
  titlePanel("Government Document Intelligence"),

  sidebarLayout(
    sidebarPanel(
      width = 3,
      h5("Document corpus"),
      uiOutput("corpus_summary"),        # populated in server: n docs, n file types
      hr(),
      h5("Filter by file type"),
      uiOutput("type_filter")            # populated in server from store metadata
    ),
    mainPanel(
      width = 9,
      # Question input
      textAreaInput(
        "question",
        label    = "Ask a question about the indexed documents:",
        rows     = 3,
        width    = "100%",
        placeholder = "e.g. What is the eligibility threshold for housing support?"
      ),
      actionButton("submit", "Search documents", class = "btn-primary"),
      br(), br(),

      # Answer panel
      shinycssloaders::withSpinner(
        uiOutput("answer_panel"),
        type = 4, color = "#1A7A6E"
      ),
      br(),

      # Source citation table
      conditionalPanel(
        condition = "output.has_sources",
        h5("Source documents retrieved"),
        DT::dataTableOutput("sources_table")
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {
  # ... see patterns below
}

shinyApp(ui, server)
```

---

## Server reactive patterns

### State object
Use a single `reactiveValues()` object for all shared state:

```r
state <- reactiveValues(
  answer         = NULL,
  sources        = NULL,
  low_confidence = FALSE,
  loading        = FALSE
)
```

### Triggering the RAG pipeline
Always trigger on the button, never on the text input:

```r
observeEvent(input$submit, {
  req(input$question)
  req(nchar(trimws(input$question)) > 0)

  state$loading <- TRUE
  state$answer  <- NULL
  state$sources <- NULL

  # Connect to store (read-only)
  store <- tryCatch(
    ragnar::ragnar_store_connect(STORE_PATH, read_only = TRUE),
    error = function(e) {
      shiny::showNotification(paste("Store error:", conditionMessage(e)), type = "error")
      NULL
    }
  )
  req(store)

  # Retrieve
  top_chunks <- tryCatch(
    ragnar::ragnar_retrieve_bm25(store, input$question, top_k = TOP_K),
    error = function(e) {
      shiny::showNotification(paste("Retrieval error:", conditionMessage(e)), type = "error")
      NULL
    }
  )

  if (is.null(top_chunks) || nrow(top_chunks) == 0) {
    state$answer  <- "No relevant content found in the indexed documents."
    state$loading <- FALSE
    return()
  }

  # Confidence flag
  state$low_confidence <- max(top_chunks$metric_value, na.rm = TRUE) < 1.0

  # Build prompt and call LLM
  prompt <- build_rag_prompt(input$question, top_chunks, state$low_confidence)
  raw    <- tryCatch(
    call_llm(prompt),
    error = function(e) {
      shiny::showNotification(paste("LLM error:", conditionMessage(e)), type = "error")
      NULL
    }
  )

  state$answer  <- if (!is.null(raw)) parse_answer(raw) else
                   "LLM call failed — check endpoint connectivity."
  state$sources <- top_chunks
  state$loading <- FALSE
})
```

### Answer panel output
```r
output$answer_panel <- renderUI({
  req(state$answer)

  warning_div <- if (isTRUE(state$low_confidence)) {
    tags$div(
      style = "color:#D4860B; font-weight:bold; margin-bottom:10px;",
      "\u26a0 Low confidence \u2014 retrieved context may not directly address this question."
    )
  } else NULL

  tags$div(
    warning_div,
    tags$div(
      style = paste(
        "background:#E6F4F1; padding:14px;",
        "border-left:5px solid #1A7A6E;",
        "border-radius:4px;",
        "font-size:15px; line-height:1.6;"
      ),
      state$answer
    )
  )
})
```

### Source citation table
```r
output$has_sources <- reactive({ !is.null(state$sources) })
outputOptions(output, "has_sources", suspendWhenHidden = FALSE)

output$sources_table <- DT::renderDataTable({
  req(state$sources)
  df <- data.frame(
    Document = basename(state$sources$origin),
    Type     = state$sources$file_type,
    Score    = round(state$sources$metric_value, 2),
    Excerpt  = substr(state$sources$text, 1, 200),
    stringsAsFactors = FALSE
  )
  DT::datatable(
    df,
    options  = list(pageLength = 5, dom = "t", scrollX = TRUE),
    rownames = FALSE,
    colnames = c("Document", "Type", "BM25 Score", "Excerpt")
  )
})
```

### Corpus summary (sidebar)
```r
output$corpus_summary <- renderUI({
  # Connect briefly to read metadata
  store <- tryCatch(
    ragnar::ragnar_store_connect(STORE_PATH, read_only = TRUE),
    error = function(e) NULL
  )
  if (is.null(store)) return(tags$p("Store not connected.", style = "color:red;"))

  # ragnar doesn't expose a direct count — query DuckDB directly
  con    <- store$con   # DuckDB connection inside ragnar store object
  n_docs <- DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT origin) AS n FROM chunks")$n
  n_chunks <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM chunks")$n

  tags$div(
    tags$p(paste0(n_docs, " documents indexed")),
    tags$p(paste0(n_chunks, " chunks searchable"))
  )
})
```

---

## Styling reference

| Element | Style |
|---|---|
| Answer panel background | `#E6F4F1` (light teal) |
| Answer panel left border | `5px solid #1A7A6E` (UKHSA teal) |
| Low-confidence warning text | `#D4860B` (amber), bold |
| Submit button | `class = "btn-primary"` (flatly theme blue — consistent) |
| Spinner colour | `#1A7A6E` |

---

## Do not patterns

| Don't | Do instead |
|---|---|
| `renderPrint(state$answer)` | `renderUI()` with styled `tags$div` |
| `observe({ input$question ... })` | `observeEvent(input$submit, ...)` |
| Calling `ragnar_store_connect()` outside a reactive context | Call inside `observeEvent` or a `reactive()` |
| Putting `STORE_PATH` inside the server function | Define at top of `app.R` as a constant |
| Using `output$x <- renderText(NULL)` for empty state | Use `req()` to suppress output until data is ready |
