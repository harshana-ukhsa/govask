# =============================================================================
# govuk_api.R — GOV.UK Content & Search API Client
# =============================================================================
#
# PURPOSE
# -------
# This script provides functions to query the GOV.UK Content API and Search API.
# It can:
#   1. Fetch content from specific GOV.UK paths (Content API)
#   2. Search GOV.UK by keywords with filters (Search API)
#   3. Extract plain text and save documents for RAG ingestion
#
# APIs Used:
#   - Content API: https://www.gov.uk/api/content/{path}
#   - Search API:  https://www.gov.uk/api/search.json
#
# No authentication required. Rate limit: 10 requests/second.
#
# USAGE
#   source("ref_code/govuk_api.R")
#
#   # Fetch a single page by path
#   doc <- fetch_govuk_content("vat-rates")
#
#   # Search GOV.UK
#   results <- search_govuk("housing benefit", count = 20)
#
#   # Download multiple documents to a folder
#   download_govuk_documents(
#     query       = "housing benefit eligibility",
#     count       = 10,
#     output_dir  = here::here("data", "govapi_files"),
#     filter_orgs = "department-for-work-pensions"
#   )
#
# =============================================================================

library(httr2)
library(rlang)
library(here)
library(xml2)
library(rvest)

# ── API Base URLs ─────────────────────────────────────────────────────────────
GOVUK_CONTENT_API <- "https://www.gov.uk/api/content"
GOVUK_SEARCH_API  <- "https://www.gov.uk/api/search.json"

# =============================================================================
# CONTENT API: Fetch a single page by path
# =============================================================================
#' Fetch content from GOV.UK by path
#'
#' @param path Character. The GOV.UK path (e.g. "vat-rates", "housing-benefit").
#'             Do not include leading slash.
#' @return A list containing the full API response (title, description, details, etc.)
#'         or NULL on error.
fetch_govuk_content <- function(path) {
  # Remove leading slash if present
  path <- sub("^/+", "", path)
  
  url <- paste0(GOVUK_CONTENT_API, "/", path)
  
  tryCatch({
    resp <- request(url) |>
      req_headers(`Accept` = "application/json") |>
      req_timeout(30) |>
      req_error(is_error = function(resp) FALSE) |>
      req_perform()
    
    status <- resp_status(resp)
    
    if (status == 200) {
      content <- resp_body_json(resp)
      message("Fetched: ", content$title %||% path)
      return(content)
    } else if (status == 303) {
      # Redirect — follow to canonical location
      location <- resp_header(resp, "Location")
      message("Redirected to: ", location)
      return(fetch_govuk_content(sub(".*/api/content/", "", location)))
    } else {
      warning("HTTP ", status, " for path: ", path)
      return(NULL)
    }
  }, error = function(e) {
    warning("Failed to fetch '", path, "': ", conditionMessage(e))
    return(NULL)
  })
}

# =============================================================================
# SEARCH API: Search GOV.UK with filters
# =============================================================================
#' Search GOV.UK Content
#'
#' @param query Character. The search query string.
#' @param count Integer. Number of results to return (default 10, max ~1500).
#' @param start Integer. Pagination offset (default 0).
#' @param filter_document_type Character. Filter by document type
#'        (e.g. "guidance", "answer", "detailed_guide", "publication").
#' @param filter_organisations Character. Filter by organisation slug
#'        (e.g. "department-for-work-pensions", "uk-health-security-agency").
#' @param filter_content_purpose_supergroup Character. Filter by content purpose
#'        (e.g. "guidance_and_regulation", "services", "news_and_communications").
#' @param fields Character vector. Fields to return (default: common fields).
#' @return A list with `results` (list of items), `total` (total matches), `start`.
search_govuk <- function(query,
                         count = 10,
                         start = 0,
                         filter_document_type = NULL,
                         filter_organisations = NULL,
                         filter_content_purpose_supergroup = NULL,
                         fields = c("title", "description", "link",
                                    "public_timestamp", "format",
                                    "document_type")) {
  
  tryCatch({
    # Build request with httr2's native query param handling
    # Note: Don't specify 'fields' - it causes 422 errors, API returns all fields by default
    req <- request(GOVUK_SEARCH_API) |>
      req_url_query(
        q      = query,
        count  = count,
        start  = start
      ) |>
      req_headers(`Accept` = "application/json") |>
      req_timeout(30) |>
      req_error(is_error = function(resp) FALSE)
    
    # Add optional filters one at a time
    if (!is.null(filter_document_type)) {
      req <- req |> req_url_query(`filter_document_type` = filter_document_type)
    }
    if (!is.null(filter_organisations)) {
      req <- req |> req_url_query(`filter_organisations` = filter_organisations)
    }
    if (!is.null(filter_content_purpose_supergroup)) {
      req <- req |> req_url_query(`filter_content_purpose_supergroup` = filter_content_purpose_supergroup)
    }
    
    message("Search URL: ", req$url)
    
    resp <- req_perform(req)
    
    status <- resp_status(resp)
    if (status == 200) {
      data <- resp_body_json(resp)
      message("Search returned ", length(data$results), " of ", data$total, " results")
      return(data)
    } else {
      warning("Search HTTP ", status)
      tryCatch({
        body <- resp_body_string(resp)
        message("Response body: ", substr(body, 1, 300))
      }, error = function(e) NULL)
      return(list(results = list(), total = 0, start = 0))
    }
  }, error = function(e) {
    warning("Search failed: ", conditionMessage(e))
    return(list(results = list(), total = 0, start = 0))
  })
}

# =============================================================================
# TEXT EXTRACTION: Convert API response to plain text
# =============================================================================
#' Extract plain text from GOV.UK content item
#'
#' @param content List. A content item from fetch_govuk_content().
#' @return Character. Plain text extracted from the content.
extract_text_from_content <- function(content) {
  if (is.null(content)) return("")
  
  parts <- character()
  
  # Title
  if (!is.null(content$title)) {
    parts <- c(parts, paste0("# ", content$title))
  }
  
  # Description
  if (!is.null(content$description)) {
    parts <- c(parts, "", content$description)
  }
  
  # Body content (usually HTML in details$body)
  if (!is.null(content$details$body)) {
    body_text <- tryCatch({
      html <- read_html(content$details$body)
      html_text(html, trim = TRUE)
    }, error = function(e) {
      # Fallback: strip tags manually
      gsub("<[^>]+>", " ", content$details$body)
    })
    parts <- c(parts, "", body_text)
  }
  
  # Parts/chapters (for multi-part guides)
  if (!is.null(content$details$parts)) {
    for (part in content$details$parts) {
      if (!is.null(part$title)) {
        parts <- c(parts, "", paste0("## ", part$title))
      }
      if (!is.null(part$body)) {
        part_text <- tryCatch({
          html <- read_html(part$body)
          html_text(html, trim = TRUE)
        }, error = function(e) {
          gsub("<[^>]+>", " ", part$body)
        })
        parts <- c(parts, "", part_text)
      }
    }
  }
  
  # Introduction (for some document types)
  if (!is.null(content$details$introduction)) {
    intro_text <- tryCatch({
      html <- read_html(content$details$introduction)
      html_text(html, trim = TRUE)
    }, error = function(e) {
      gsub("<[^>]+>", " ", content$details$introduction)
    })
    parts <- c(parts, "", intro_text)
  }
  
  # Summary (for news articles)
  if (!is.null(content$details$summary)) {
    summary_text <- tryCatch({
      html <- read_html(content$details$summary)
      html_text(html, trim = TRUE)
    }, error = function(e) {
      gsub("<[^>]+>", " ", content$details$summary)
    })
    parts <- c(parts, "", summary_text)
  }
  
  # Documents collection (for publications)
  if (!is.null(content$details$documents)) {
    for (doc in content$details$documents) {
      if (is.character(doc)) {
        doc_text <- tryCatch({
          html <- read_html(doc)
          html_text(html, trim = TRUE)
        }, error = function(e) {
          gsub("<[^>]+>", " ", doc)
        })
        parts <- c(parts, "", doc_text)
      }
    }
  }
  
  # Clean up and collapse
  text <- paste(parts, collapse = "\n")
  text <- gsub("\\s+", " ", text)
  text <- gsub("\n +", "\n", text)
  trimws(text)
}

# =============================================================================
# DOWNLOAD: Fetch and save documents for RAG ingestion
# =============================================================================
#' Download GOV.UK documents to a folder
#'
#' Searches GOV.UK, fetches full content for each result, extracts text,
#' and saves as individual files for RAG ingestion.
#'
#' @param query Character. Search query.
#' @param count Integer. Number of documents to download (default 10).
#' @param output_dir Character. Directory to save files (default: data/govapi_files).
#' @param filter_document_type Character. Optional document type filter.
#' @param filter_organisations Character. Optional organisation filter.
#' @param filter_content_purpose_supergroup Character. Optional content purpose filter.
#' @param file_format Character. Output format: "txt" or "md" (default "txt").
#' @param delay Numeric. Seconds to wait between API calls (default 0.15 for rate limit).
#' @return Character vector of saved file paths.
download_govuk_documents <- function(query,
                                     count = 10,
                                     output_dir = here::here("data", "govapi_files"),
                                     filter_document_type = NULL,
                                     filter_organisations = NULL,
                                     filter_content_purpose_supergroup = NULL,
                                     file_format = "txt",
                                     delay = 0.15) {
  
  message("download_govuk_documents() called")
  message("  query: ", query)
  message("  count: ", count)
  message("  output_dir: ", output_dir)
  message("  filter_organisations: ", filter_organisations %||% "(none)")
  
  # Create output directory if needed
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    message("Created directory: ", output_dir)
  }
  
  # Search for documents
  message("Calling search_govuk()...")
  search_results <- search_govuk(
    query = query,
    count = count,
    filter_document_type = filter_document_type,
    filter_organisations = filter_organisations,
    filter_content_purpose_supergroup = filter_content_purpose_supergroup
  )
  
  message("Search complete. Results: ", length(search_results$results))
  
  if (length(search_results$results) == 0) {
    message("No results found for query: ", query)
    return(character())
  }
  
  saved_files <- character()
  
  for (i in seq_along(search_results$results)) {
    result <- search_results$results[[i]]
    path <- sub("^/+", "", result$link)
    
    message("\n[", i, "/", length(search_results$results), "] Fetching: ", path)
    
    # Fetch full content
    content <- fetch_govuk_content(path)
    
    if (is.null(content)) {
      message("  Skipped (fetch failed)")
      next
    }
    
    message("  Document type: ", content$document_type %||% "unknown")
    
    # Extract text
    text <- extract_text_from_content(content)
    
    message("  Extracted text length: ", nchar(text), " chars")
    
    if (nchar(text) < 50) {
      message("  Skipped (insufficient content - need at least 50 chars)")
      next
    }
    
    # Generate filename: sanitise path to valid filename
    safe_name <- gsub("[^a-zA-Z0-9_-]", "_", path)
    safe_name <- gsub("_+", "_", safe_name)
    safe_name <- sub("^_", "", safe_name)
    safe_name <- substr(safe_name, 1, 100)  # Limit length
    filename <- paste0("GOVUK-", safe_name, ".", file_format)
    filepath <- file.path(output_dir, filename)
    
    # Add metadata header
    header <- paste0(
      "---\n",
      "source: GOV.UK\n",
      "url: https://www.gov.uk", result$link, "\n",
      "title: ", content$title %||% "Untitled", "\n",
      "document_type: ", content$document_type %||% "unknown", "\n",
      "fetched: ", Sys.time(), "\n",
      "---\n\n"
    )
    
    # Write file
    writeLines(paste0(header, text), filepath)
    message("  Saved: ", filename)
    saved_files <- c(saved_files, filepath)
    
    # Rate limit delay
    if (i < length(search_results$results)) {
      Sys.sleep(delay)
    }
  }
  
  message("\n", length(saved_files), " document(s) saved to ", output_dir)
  return(saved_files)
}

# =============================================================================
# CONVENIENCE: Fetch by paths (for known URLs)
# =============================================================================
#' Download specific GOV.UK pages by path
#'
#' @param paths Character vector. GOV.UK paths to fetch.
#' @param output_dir Character. Directory to save files.
#' @param file_format Character. Output format: "txt" or "md".
#' @param delay Numeric. Seconds between requests.
#' @return Character vector of saved file paths.
download_govuk_by_paths <- function(paths,
                                    output_dir = here::here("data", "govapi_files"),
                                    file_format = "txt",
                                    delay = 0.15) {
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  saved_files <- character()
  
  for (i in seq_along(paths)) {
    path <- sub("^/+", "", paths[i])
    message("\n[", i, "/", length(paths), "] Fetching: ", path)
    
    content <- fetch_govuk_content(path)
    
    if (is.null(content)) {
      message("  Skipped (fetch failed)")
      next
    }
    
    text <- extract_text_from_content(content)
    
    if (nchar(text) < 50) {
      message("  Skipped (insufficient content)")
      next
    }
    
    safe_name <- gsub("[^a-zA-Z0-9_-]", "_", path)
    safe_name <- gsub("_+", "_", safe_name)
    safe_name <- sub("^_", "", safe_name)
    safe_name <- substr(safe_name, 1, 100)
    filename <- paste0("GOVUK-", safe_name, ".", file_format)
    filepath <- file.path(output_dir, filename)
    
    header <- paste0(
      "---\n",
      "source: GOV.UK\n",
      "url: https://www.gov.uk/", path, "\n",
      "title: ", content$title %||% "Untitled", "\n",
      "document_type: ", content$document_type %||% "unknown", "\n",
      "fetched: ", Sys.time(), "\n",
      "---\n\n"
    )
    
    writeLines(paste0(header, text), filepath)
    message("  Saved: ", filename)
    saved_files <- c(saved_files, filepath)
    
    if (i < length(paths)) {
      Sys.sleep(delay)
    }
  }
  
  message("\n", length(saved_files), " document(s) saved")
  return(saved_files)
}

# =============================================================================
# EXAMPLE USAGE (uncomment to run)
# =============================================================================
# # Search and download housing benefit guidance
# download_govuk_documents(
#   query       = "housing benefit",
#   count       = 15,
#   output_dir  = here::here("data", "govapi_files"),
#   filter_content_purpose_supergroup = "guidance_and_regulation"
# )
#
# # Fetch specific known pages
# download_govuk_by_paths(
#   paths = c(
#     "housing-benefit",
#     "housing-benefit/what-youll-get",
#     "apply-housing-benefit-from-council",
#     "council-tax-reduction"
#   ),
#   output_dir = here::here("data", "govapi_files")
# )

message("GOV.UK API functions loaded. Use ?search_govuk or ?download_govuk_documents for help.")
