library(shiny)
library(bslib)
library(DT)
library(shinycssloaders)
library(shinyjs)

# ── GOV.UK Design System colours ──────────────────────────────────────────────
GOVUK_BLACK  <- "#0b0c0c"
GOVUK_BLUE   <- "#1d70b8"
GOVUK_GREEN  <- "#00703c"
GOVUK_RED    <- "#d4351c"

# ── GOV.UK CSS ────────────────────────────────────────────────────────────────
govuk_css <- tags$style(HTML("
  /* ── Typography ─────────────────────────────────────────────────────────── */
  body, .shiny-input-container, .navbar, .sidebar, .well {
    font-family: 'GDS Transport', Arial, sans-serif !important;
    color: #0b0c0c;
  }

  /* ── Navbar — black GOV.UK header bar ─────────────────────────────────── */
  .navbar {
    background-color: #0b0c0c !important;
    border: none !important;
    border-bottom: 10px solid #1d70b8 !important;
    padding-top: 10px !important;
    padding-bottom: 10px !important;
    margin-bottom: 0 !important;
    /* force horizontal on all viewport widths */
  }
  .navbar-toggler { display: none !important; }
  .navbar-collapse { display: flex !important; }

  /* brand — GOV.UK logotype area */
  .navbar-brand {
    font-weight: 700 !important;
    font-size: 20px !important;
    color: #ffffff !important;
    line-height: 1 !important;
    padding-top: 4px !important;
    padding-bottom: 0 !important;
  }

  /* tab links sit in the navbar */
  .navbar .nav-link {
    color: #ffffff !important;
    font-weight: 400;
    font-size: 15px;
    padding: 10px 15px !important;
    border-bottom: 4px solid transparent;
    transition: border-color 0.1s;
  }
  .navbar .nav-link:hover          { border-bottom-color: #ffdd00; }
  .navbar .nav-link.active,
  .navbar .nav-item.show .nav-link { border-bottom-color: #ffdd00 !important; font-weight: 700; }

  /* ── BETA phase banner ───────────────────────────────────────────────────── */
  .govuk-phase-banner {
    background: #f3f2f1;
    border-bottom: 1px solid #b1b4b6;
    padding: 6px 20px;
    font-family: 'GDS Transport', Arial, sans-serif;
    font-size: 14px;
    line-height: 1.6;
  }
  .govuk-tag {
    display: inline-block;
    background: #1d70b8;
    color: #ffffff;
    padding: 2px 8px;
    font-size: 12px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-right: 8px;
    border-radius: 0;
  }

  /* ── Page background ─────────────────────────────────────────────────────── */
  body { background-color: #ffffff; }

  /* ── Sidebar ─────────────────────────────────────────────────────────────── */
  .well { background-color: #f3f2f1; border: none; border-radius: 0; box-shadow: none; }

  /* ── Section headings ───────────────────────────────────────────────────── */
  h3, h4, h5 { color: #0b0c0c; }
  hr { border-top: 2px solid #b1b4b6; }

  /* ── Primary action button — GOV.UK green ───────────────────────────────── */
  .btn-primary {
    background-color: #00703c !important;
    border-color: #00703c !important;
    color: #ffffff !important;
    border-radius: 0 !important;
    font-weight: 700 !important;
    font-size: 16px;
    padding: 8px 16px;
    box-shadow: 0 2px 0 #002d18 !important;
  }
  .btn-primary:hover  { background-color: #005a30 !important; border-color: #005a30 !important; }
  .btn-primary:focus  { outline: 3px solid #ffdd00 !important; outline-offset: 0 !important; }
  .btn-primary:active { box-shadow: none !important; top: 2px; position: relative; }

  /* ── Links ───────────────────────────────────────────────────────────────── */
  a               { color: #1d70b8; }
  a:hover         { color: #003078; }
  a:visited       { color: #4c2c92; }
  a:focus         { background: #ffdd00; outline: 3px solid #ffdd00; outline-offset: 0; }

  /* ── Text inputs ─────────────────────────────────────────────────────────── */
  textarea.form-control, input.form-control {
    border: 2px solid #0b0c0c;
    border-radius: 0;
  }
  textarea.form-control:focus, input.form-control:focus {
    outline: 3px solid #ffdd00;
    outline-offset: 0;
    box-shadow: none;
  }

  /* ── Answer citation expander ────────────────────────────────────────────── */
  details > summary { list-style: none; }
  details > summary::-webkit-details-marker { display: none; }

  /* ── DT table ────────────────────────────────────────────────────────────── */
  .dataTables_wrapper { font-size: 14px; }
"))

# ── JavaScript for tab and input persistence after reload ─────────────────────
tab_persistence_js <- tags$script(HTML("
  $(document).ready(function() {
    // On page load, check if we need to switch to a specific tab
    var savedTab = sessionStorage.getItem('govask_active_tab');
    if (savedTab) {
      sessionStorage.removeItem('govask_active_tab');
      // Use Bootstrap 5 tab API to activate the saved tab
      var tabLink = document.querySelector('a.nav-link[data-value=\"' + savedTab + '\"]');
      if (tabLink) {
        var tab = new bootstrap.Tab(tabLink);
        tab.show();
      }
    }
    
    // Restore APIAsk inputs if saved
    var savedSearchTerms = sessionStorage.getItem('govask_api_search_terms');
    var savedFilterOrg = sessionStorage.getItem('govask_api_filter_org');
    var savedDocCount = sessionStorage.getItem('govask_api_doc_count');
    
    if (savedSearchTerms !== null) {
      $('#api_search_terms').val(savedSearchTerms);
      sessionStorage.removeItem('govask_api_search_terms');
    }
    
    if (savedFilterOrg !== null) {
      $('#api_filter_org').val(savedFilterOrg);
      sessionStorage.removeItem('govask_api_filter_org');
    }
    
    if (savedDocCount !== null) {
      // Update slider value - Shiny sliders use a specific structure
      var slider = $('#api_doc_count');
      if (slider.length) {
        // For Shiny sliderInput, we need to update via Shiny's input binding
        Shiny.setInputValue('api_doc_count', parseInt(savedDocCount));
      }
      sessionStorage.removeItem('govask_api_doc_count');
    }
  });
"))

# ── BETA phase banner ─────────────────────────────────────────────────────────
govuk_beta_banner <- tags$div(
  class = "govuk-phase-banner",
  tags$span(class = "govuk-tag", "BETA"),
  "This is a new service — your feedback will help us to improve it."
)

# ── Reusable tab panel builder ────────────────────────────────────────────────
# Builds a consistent sidebarLayout panel for any RAG tab.
# All output IDs are namespaced with `ns_` to avoid collisions between tabs.
rag_tab_panel <- function(
  tab_title,
  full_title,
  ns,                  # namespace prefix string, e.g. "gov" or "epi"
  description = NULL,  # optional 2-3 sentence description of the service
  question_placeholder = "e.g. What is the eligibility threshold for housing support?"
) {
  bslib::nav_panel(
    tab_title,
    govuk_beta_banner,
    br(),
    sidebarLayout(
      sidebarPanel(
        width = 3,
        h5("Document corpus"),
        uiOutput(paste0(ns, "_corpus_summary")),
        hr(),
        h5("Document themes"),
        uiOutput(paste0(ns, "_categories")),
        hr(),
        h5("Filter by file type"),
        uiOutput(paste0(ns, "_type_filter"))
      ),
      mainPanel(
        width = 9,
        h3(full_title),
        hr(),
        
        # ── Service description ────────────────────────────────────────────
        if (!is.null(description)) {
          tags$p(
            style = "font-size: 16px; color: #505a5f; margin-bottom: 20px; line-height: 1.5;",
            description
          )
        },

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
          color = GOVUK_BLUE
        ),
        br(),

        # ── Source citation table (collapsible) ────────────────────────────
        conditionalPanel(
          condition = paste0("output.", ns, "_has_sources"),
          tags$details(
            tags$summary(
              style = paste(
                "font-size:15px; font-weight:600;",
                "cursor:pointer; margin-bottom:8px;"
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
  id = "main_nav",
  title = HTML(paste0(
    '<span style="font-weight:700;font-size:20px;color:#fff;',
    'font-family:\'GDS Transport\',Arial,sans-serif;">GOV.UK</span>',
    '<span style="font-size:13px;font-weight:400;color:#fff;',
    'border-left:1px solid #6f777b;margin-left:12px;padding-left:12px;',
    'font-family:\'GDS Transport\',Arial,sans-serif;">',
    'Document Intelligence</span>'
  )),
  theme = bslib::bs_theme(
    version  = 5,
    bg       = "#ffffff",
    fg       = "#0b0c0c",
    primary  = GOVUK_BLUE,
    success  = GOVUK_GREEN,
    danger   = GOVUK_RED,
    "navbar-bg"          = GOVUK_BLACK,
    "navbar-color"       = "#ffffff",
    "navbar-brand-color" = "#ffffff",
    "border-radius"      = "0px",
    "font-family-sans-serif" = "'GDS Transport', Arial, sans-serif"
  ),
  fluid  = TRUE,
  header = tagList(shinyjs::useShinyjs(), govuk_css, tab_persistence_js),

  rag_tab_panel(
    tab_title            = "GovAsk",
    full_title           = "GovAsk \u2014 Government Document Intelligence",
    ns                   = "gov",
    description          = "Search and query government guidance documents using natural language. This service retrieves relevant content from indexed policy documents and generates answers grounded in official sources. All responses include citations to the original documents.",
    question_placeholder = "e.g. What is the eligibility threshold for housing support?"
  ),

  rag_tab_panel(
    tab_title            = "EpiAsk",
    full_title           = "EpiAsk \u2014 EpiDS Document Intelligence",
    ns                   = "epi",
    description          = "Query epidemiological and public health documents from the EpiDS collection. This service helps you find information from surveillance reports, methodological guidance, and analytical outputs. Answers are generated from indexed documents with full source attribution.",
    question_placeholder = "e.g. What are the methods used in the latest EpiDS report?"
  ),

  # API tab with custom info box showing query parameters
 bslib::nav_panel(
    "APIAsk",
    br(),
    sidebarLayout(
      sidebarPanel(
        width = 3,
        h5("GOV.UK API Query"),
        tags$p(
          style = "font-size: 12px; color: #505a5f; margin-bottom: 10px;",
          "Configure the GOV.UK API search parameters below, then click 'Fetch Documents' to download and index content."
        ),
        
        # Search terms input
        textInput(
          inputId     = "api_search_terms",
          label       = "Search terms:",
          value       = "health protection guidance",
          placeholder = "e.g. infection control, vaccination"
        ),
        
        # Organisation filter dropdown
        selectInput(
          inputId  = "api_filter_org",
          label    = "Filter by organisation:",
          choices  = c(
            "No filter (all organisations)" = "",
            "UK Health Security Agency" = "uk-health-security-agency",
            "Department of Health and Social Care" = "department-of-health-and-social-care",
            "NHS England" = "nhs-england",
            "Public Health Wales" = "public-health-wales",
            "Public Health Scotland" = "public-health-scotland",
            "Health and Safety Executive" = "health-and-safety-executive",
            "Food Standards Agency" = "food-standards-agency",
            "Medicines and Healthcare products Regulatory Agency" = "medicines-and-healthcare-products-regulatory-agency",
            "Office for Health Improvement and Disparities" = "office-for-health-improvement-and-disparities",
            "Care Quality Commission" = "care-quality-commission",
            "National Institute for Health and Care Excellence" = "national-institute-for-health-and-care-excellence",
            "Health Education England" = "health-education-england",
            "NHS Digital" = "nhs-digital",
            "Office for National Statistics" = "office-for-national-statistics",
            "Home Office" = "home-office",
            "Department for Environment, Food & Rural Affairs" = "department-for-environment-food-rural-affairs",
            "Cabinet Office" = "cabinet-office"
          ),
          selected = ""
        ),
        
        # Number of documents
        sliderInput(
          inputId = "api_doc_count",
          label   = "Number of documents:",
          min     = 5,
          max     = 50,
          value   = 20,
          step    = 5
        ),
        
        # Fetch button
        actionButton(
          "api_fetch_docs", 
          "Fetch Documents", 
          class = "btn-primary",
          style = "width: 100%; margin-top: 10px;"
        ),
        
        # Status message
        uiOutput("api_fetch_status"),
        
        hr(),
        h5("Document corpus"),
        uiOutput("api_corpus_summary"),
        hr(),
        h5("Filter by file type"),
        uiOutput("api_type_filter")
      ),
      mainPanel(
        width = 9,
        h3("APIAsk \u2014 GOV.UK API Document Intelligence"),
        hr(),
        tags$p(
          style = "font-size: 16px; color: #505a5f; margin-bottom: 20px; line-height: 1.5;",
          "Access government guidance documents fetched directly from the GOV.UK API. Configure your search in the sidebar to retrieve documents from any government organisation. Documents are indexed for natural language querying with full source attribution."
        ),
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
