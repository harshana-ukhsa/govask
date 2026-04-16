---
applyTo: "app.R, ui.R, server.R"
---

# Shiny UI & Server Conventions

## App structure

Split into three files when the app grows beyond a single screen. For this project, a single `app.R` is acceptable during the hackathon:

```r
# app.R
library(shiny)
library(bslib)

ui <- fluidPage(...)
server <- function(input, output, session) { ... }
shinyApp(ui, server)
```

## Theme

Always apply a bslib theme for a clean, professional appearance:

```r
ui <- fluidPage(
  theme = bslib::bs_theme(bootswatch = "flatly"),
  ...
)
```

Do not use inline CSS for layout — use bslib layout helpers (`layout_sidebar`, `card`, `value_box`) where possible.

## Required UI components for the RAG interface

```r
# Question input
textAreaInput("question", label = "Ask a question about the documents:", rows = 3,
              placeholder = "e.g. What is the eligibility threshold for housing support?")

# Submit button
actionButton("submit", "Search documents", class = "btn-primary")

# Answer panel — wrap in spinner for loading state
shinycssloaders::withSpinner(
  uiOutput("answer"),
  type = 4, color = "#1A7A6E"
)

# Source citation table
DT::dataTableOutput("sources")
```

## Answer panel styling

Render answers in a styled div, not plain `verbatimTextOutput`:

```r
output$answer <- renderUI({
  tags$div(
    style = "background:#E6F4F1; padding:14px; border-left:5px solid #1A7A6E;
             border-radius:4px; font-size:15px; line-height:1.6;",
    answer_text
  )
})
```

If the answer contains a low-confidence warning, render it in amber before the answer text:

```r
tags$div(
  style = "color:#D4860B; font-weight:bold; margin-bottom:8px;",
  "⚠ Low confidence — the retrieved context may not directly address this question."
)
```

## Source citation table

The `sources` output should show a `DT::datatable` with these columns:

| Column | Source | Notes |
|---|---|---|
| Document | `basename(origin)` | Filename only, not full path |
| Type | `file_type` metadata | e.g. pdf, docx, md |
| Score | `round(metric_value, 2)` | BM25 relevance score |
| Excerpt | `substr(text, 1, 200)` | First 200 chars of chunk |

```r
output$sources <- DT::renderDataTable({
  DT::datatable(
    sources_df,
    options = list(pageLength = 5, dom = "t"),
    rownames = FALSE,
    colnames = c("Document", "Type", "Score", "Excerpt")
  )
})
```

## Reactive patterns

- Always trigger on `input$submit` using `eventReactive()` or `observeEvent()` — never on `input$question` directly (avoids firing on every keystroke).
- Always guard inputs with `req()` before any computation:

```r
observeEvent(input$submit, {
  req(input$question)
  req(nchar(trimws(input$question)) > 0)
  # proceed with retrieval
})
```

- Store the answer and sources in a `reactiveValues()` object, not separate `reactive()` calls:

```r
state <- reactiveValues(answer = NULL, sources = NULL, loading = FALSE)
```

## Error handling in the server

- Never let an error crash the app. Wrap all ragnar and LLM calls in `tryCatch()`.
- Surface errors to the user with `shiny::showNotification()`:

```r
shiny::showNotification(
  paste("Error:", conditionMessage(e)),
  type = "error",
  duration = 8
)
```

- If the store is not found on startup, show a clear message in the UI — do not silently fail.

## Do not do

- Do not use `renderPrint()` for the main answer output — use `renderUI()` for styled HTML.
- Do not use `observe()` watching `input$question` — use `observeEvent(input$submit, ...)`.
- Do not put file path constants inside the server function — define them at the top of `app.R`.
- Do not use `global.R` for this project — keep everything in `app.R` during the hackathon.
