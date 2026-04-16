---
marp: true
theme: default
paginate: true
style: |
  /* ── GOV.UK Design System theme ─────────────────────────────────────── */
  @import url('https://fonts.googleapis.com/css2?family=Noto+Sans:wght@400;700&display=swap');

  :root {
    --govuk-black:        #0b0c0c;
    --govuk-blue:         #1d70b8;
    --govuk-green:        #00703c;
    --govuk-yellow:       #ffdd00;
    --govuk-red:          #d4351c;
    --govuk-light-grey:   #f3f2f1;
    --govuk-mid-grey:     #b1b4b6;
    --govuk-dark-grey:    #505a5f;
    --govuk-white:        #ffffff;
  }

  section {
    font-family: "GDS Transport", "Noto Sans", Arial, sans-serif;
    font-size: 26px;
    color: var(--govuk-black);
    background: var(--govuk-white);
    padding: 48px 64px 48px 64px;
    border-top: 10px solid var(--govuk-black);
  }

  section h1 {
    font-size: 42px;
    font-weight: 700;
    color: var(--govuk-black);
    border-bottom: 4px solid var(--govuk-blue);
    padding-bottom: 10px;
    margin-bottom: 24px;
    line-height: 1.1;
  }

  section h2 {
    font-size: 32px;
    font-weight: 700;
    color: var(--govuk-black);
  }

  section h3 {
    font-size: 26px;
    font-weight: 700;
    color: var(--govuk-blue);
  }

  /* Cover slide — GOV.UK black top bar style */
  section.cover {
    background: var(--govuk-black);
    color: var(--govuk-white);
    justify-content: flex-start;
    text-align: left;
    border-top: none;
    padding: 56px 64px;
  }
  section.cover h1 {
    color: var(--govuk-white);
    border-bottom: 4px solid var(--govuk-blue);
    font-size: 52px;
    margin-bottom: 12px;
  }
  section.cover h2 {
    color: var(--govuk-yellow);
    font-size: 30px;
    font-weight: 400;
    margin-bottom: 32px;
  }
  section.cover p {
    color: #c8c8c8;
    font-size: 22px;
    line-height: 1.5;
  }

  /* Section divider */
  section.section-divider {
    background: var(--govuk-blue);
    color: var(--govuk-white);
    justify-content: center;
    text-align: left;
    border-top: none;
  }
  section.section-divider h1 {
    color: var(--govuk-white);
    border-bottom: 3px solid rgba(255,255,255,0.4);
    font-size: 48px;
  }

  /* Tables */
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 21px;
  }
  th {
    background: var(--govuk-blue);
    color: var(--govuk-white);
    padding: 10px 14px;
    text-align: left;
    font-weight: 700;
  }
  td {
    padding: 8px 14px;
    border-bottom: 1px solid var(--govuk-mid-grey);
  }
  tr:nth-child(even) td {
    background: var(--govuk-light-grey);
  }

  /* Code */
  code {
    background: var(--govuk-light-grey);
    color: var(--govuk-black);
    padding: 2px 6px;
    border-radius: 0;
    font-size: 22px;
    font-family: monospace;
  }
  pre {
    background: var(--govuk-light-grey);
    border-left: 4px solid var(--govuk-blue);
    padding: 14px 18px;
    font-size: 20px;
  }

  /* Blockquote — GOV.UK inset text style */
  blockquote {
    border-left: 10px solid var(--govuk-mid-grey);
    background: var(--govuk-light-grey);
    padding: 12px 20px;
    margin: 16px 0;
    color: var(--govuk-black);
    font-style: normal;
  }

  /* Warning tag */
  .warning {
    color: var(--govuk-red);
    font-weight: bold;
  }

  /* Page number */
  section::after {
    color: var(--govuk-dark-grey);
    font-size: 18px;
  }

  footer {
    font-size: 18px;
    color: var(--govuk-dark-grey);
  }
---

<!-- _class: cover -->
<!-- _paginate: false -->

# GovAsk
## Government Document Intelligence

AI Engineering Lab Hackathon 2026
Challenge 2: Unlocking the Dark Data

**Team EpiDS: Harshana Liyanage · Emma Parker · Frederick Sloots**
UKHSA Epidemiology Data Science

---

# The problem

A government frontline adviser is on a call. They find three documents with similar names and different dates. They're not sure which is current.

> They give an answer based on whichever version they found fastest.
> It may not be the right one.

This is not a failure of effort. **It is a failure of infrastructure.**

---

# What we built

A single Shiny app with **three complementary interfaces**:

- **GovAsk** — query a curated local corpus of government guidance; every answer cites its source
- **APIAsk** — fetches live UKHSA guidance from the GOV.UK API on startup; always current, no manual uploads
- **EpiAsk** — same pipeline pointed at internal documents; our path to querying UKHSA's Confluence knowledge base

All grounded in retrieved documents · all answers cite sources · BM25 confidence detection throughout

---

# Architecture

```
Local files · GOV.UK API · Internal docs
    ↓  rag_setup / api_setup / epi_setup — extract & chunk
rag_store.duckdb · api_store.duckdb · epids_store.duckdb
    ↓  rag_query.R — shared retrieval + prompt + LLM
    ↓  R/app.R — GovAsk │ APIAsk │ EpiAsk
```

**APIAsk:** on startup → GOV.UK Search API → Content API → live BM25 index

Internally-hosted LLM on OpenShift AI — no data leaves the network.
Indexed in **< 2 minutes** · query response **< 5 seconds**

---

# How GitHub Copilot shaped this build

**.github/ setup before the first line of new code:**

| Layer | File | Purpose |
|---|---|---|
| Always-on | `copilot-instructions.md` | Architecture, packages, LLM endpoint, conventions |
| File-scoped | `.instructions.md` × 3 | R standards · Shiny patterns · RAG pipeline rules |
| On-demand | `Skills` × 3 | Prompt engineering · UI components · presentation |

**What changed:** The GOV.UK API client, three-tab Shiny server, and all prompt engineering were generated in Agent mode using purpose-built Skills. Two team members built different tabs in parallel — consistent output because the Skills defined the contract in advance.

---

# Security and data governance

- **No data leaves the internal network** — GPT-OSS 120B on UKHSA's OpenShift AI cluster
- **Zero commercial training use** — architectural guarantee, not a vendor promise
- **Credentials never in version control** — `.Renviron` git-ignored
- **Read-only store connections** — Shiny app cannot corrupt the index
- **GOV.UK API calls are read-only and public** — no authentication, no data submission

> Self-hosted model = query data categorically cannot be used for commercial training, regardless of any future vendor terms change.

---

# Beyond the hackathon

**Our team's next step:** connect EpiAsk to UKHSA's **Confluence REST API**
→ instant cited answers from SOPs, data standards, and surveillance system docs
→ no architecture changes — one new folder, one new setup script, one new tab

**Roadmap:**

1. **Confluence integration** — live institutional knowledge queries
2. **Audit logging** — governance requirement, not a feature
3. **Hybrid retrieval** — BM25 + semantic re-ranking, closes synonym gap
4. **Evaluation framework** — controlled model upgrade process

**Before operational deployment:**
IG review · WCAG 2.1 AA audit · Human-in-the-loop policy

---

# Team

| Person | Role |
|---|---|
| **Harshana Liyanage** | RAG architecture, prompt engineering, AI domain expertise |
| **Emma Parker** | Project management, Shiny UI, demo coordination |
| **Frederick Sloots** | Multi-format ingestion, file-type extensions |

Built with `ragnar` · `ellmer` · `R Shiny` · `DuckDB` · `GitHub Copilot`

*AI Engineering Lab Hackathon · London · April 2026*
