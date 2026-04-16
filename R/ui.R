library(shiny)
library(bslib)
library(DT)
library(shinycssloaders)

# ── Reusable tab panel builder ────────────────────────────────────────────────
# Builds a consistent sidebarLayout panel for any RAG tab.
# All output IDs are namespaced with `ns_` to avoid collisions between tabs.
rag_tab_panel <- function(
  tab_title,
  full_title,
  ns,                  # namespace prefix string, e.g. "gov" or "epi"
  question_placeholder = "e.g. What is the eligibility threshold for housing support?"
) {
  bslib::nav_panel(
    tab_title,
    br(),
    sidebarLayout(
      sidebarPanel(
        width = 3,
        h5("Document corpus"),
        uiOutput(paste0(ns, "_corpus_summary")),
        hr(),
        h5("Filter by file type"),
        uiOutput(paste0(ns, "_type_filter"))
      ),
      mainPanel(
        width = 9,
        h3(full_title),
        hr(),

        # ── Question input ─────────────────────────────────────────────────
        textAreaInput(
          inputId     = paste0(ns, "_question"),
          label       = "Ask a question about the indexed documents:",
          rows        = 3,
          width       = "100%",
          placeholder = question_placeholder
        ),
        actionButton(paste0(ns, "_submit"), "Search documents", class = "btn-primary"),
        br(), br(),

        # ── Answer panel ───────────────────────────────────────────────────
        shinycssloaders::withSpinner(
          uiOutput(paste0(ns, "_answer_panel")),
          type  = 4,
          color = "#1A7A6E"
        ),
        br(),

        # ── Source citation table (collapsible) ────────────────────────────
        conditionalPanel(
          condition = paste0("output.", ns, "_has_sources"),
          tags$details(
            tags$summary(
              style = paste(
                "font-size:15px; font-weight:600;",
                "cursor:pointer; margin-bottom:8px;",
                "list-style:none;"
              ),
              "\u25BC Source documents retrieved"
            ),
            DT::dataTableOutput(paste0(ns, "_sources_table"))
          )
        )
      )
    )
  )
}

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- bslib::page_navbar(
  title  = "GovAsk",
  theme  = bslib::bs_theme(bootswatch = "flatly"),
  fluid  = TRUE,
  header = tags$style(HTML("
    .navbar-toggler { display: none !important; }
    .navbar-collapse { display: flex !important; }
  ")),

  rag_tab_panel(
    tab_title            = "GovAsk",
    full_title           = "GovAsk \u2014 Government Document Intelligence",
    ns                   = "gov",
    question_placeholder = "e.g. What is the eligibility threshold for housing support?"
  ),

  rag_tab_panel(
    tab_title            = "EpiAsk",
    full_title           = "EpiAsk \u2014 EpiDS Document Intelligence",
    ns                   = "epi",
    question_placeholder = "e.g. What are the methods used in the latest EpiDS report?"
  ),

  # API tab with custom info box showing query parameters
 bslib::nav_panel(
    "APIAsk",
    br(),
    sidebarLayout(
      sidebarPanel(
        width = 3,
        h5("Document corpus"),
        uiOutput("api_corpus_summary"),
        hr(),
        h5("Filter by file type"),
        uiOutput("api_type_filter"),
        hr(),
        h5("GOV.UK API Query"),
        tags$div(
          style = "font-size: 12px; background: #f5f5f5; padding: 10px; border-radius: 4px;",
          tags$p(tags$strong("Query:"), " health protection guidance"),
          tags$p(tags$strong("Filter:"), " uk-health-security-agency"),
          tags$p(tags$strong("Count:"), " 20 documents"),
          tags$p(
            tags$strong("Endpoint:"), 
            tags$br(),
            tags$code("gov.uk/api/search.json", style = "font-size: 11px;")
          )
        )
      ),
      mainPanel(
        width = 9,
        h3("APIAsk \u2014 GOV.UK API Document Intelligence (UKHSA)"),
        hr(),
        textAreaInput(
          inputId     = "api_question",
          label       = "Ask a question about the indexed documents:",
          rows        = 3,
          width       = "100%",
          placeholder = "e.g. What guidance does UKHSA provide on infection control?"
        ),
        actionButton("api_submit", "Search documents", class = "btn-primary"),
        br(), br(),
        shinycssloaders::withSpinner(
          uiOutput("api_answer_panel"),
          type  = 4,
          color = "#1A7A6E"
        ),
        br(),
        conditionalPanel(
          condition = "output.api_has_sources",
          tags$details(
            tags$summary(
              style = paste(
                "font-size:15px; font-weight:600;",
                "cursor:pointer; margin-bottom:8px;",
                "list-style:none;"
              ),
              "\u25BC Source documents retrieved"
            ),
            DT::dataTableOutput("api_sources_table")
          )
        )
      )
    )
  )
)
