# Skill: RAG Prompt Engineering for Government Documents

## When to use this skill

Load this skill when asked to:
- Write or improve `build_rag_prompt()`
- Add source citations to answers
- Adjust the system instruction (grounding, fallback, tone)
- Tune `top_k` or chunk size
- Evaluate whether answers are hallucinating
- Write test questions to assess retrieval quality

---

## Core principles for government document RAG

### 1. Ground the answer — no escape hatch
The LLM must be given no route to draw on training knowledge. The grounding instruction must be absolute:

```
Answer the question using ONLY the information in the context below.
Do not use any knowledge from outside the provided context.
```

A softer instruction like "try to use the context" or "prefer the context" will produce hallucinated answers. Use the absolute form.

### 2. Explicit fallback — no guessing
The fallback must be a specific phrase the parser can detect:

```
If the answer is not in the context, say exactly:
"I cannot answer this from the provided documents."
```

This phrase is used in `parse_answer()` to detect out-of-scope questions. Do not change it without also updating the parser.

### 3. Source citation — auditable answers
Government guidance answers must be traceable. Instruct the LLM to begin with the source:

```
Begin your answer with: "According to [document name]..."
where [document name] is the filename of the most relevant source document.
```

The document name is passed via the context block header — see the template below.

### 4. Conciseness — officials are busy
```
Keep your answer to 3 sentences or fewer unless a numbered list is more appropriate.
Do not explain how you found the answer.
Do not repeat the question back.
```

### 5. No mention of the context mechanism
```
Do not refer to "the context", "the provided documents", or "the passages".
Write as if answering directly.
```

---

## Prompt template

```r
build_rag_prompt <- function(question, chunks_tbl, low_confidence = FALSE) {
  # Label each chunk with its source filename
  context_blocks <- mapply(function(text, origin) {
    paste0("--- Source: ", basename(origin), " ---\n", text)
  }, chunks_tbl$text, chunks_tbl$origin, SIMPLIFY = FALSE)

  context <- paste(context_blocks, collapse = "\n\n")

  # Prepend a warning if BM25 scores are weak
  confidence_note <- if (low_confidence) {
    paste0(
      "Note: the retrieved context may not directly address this question. ",
      "Answer only what the context supports.\n\n"
    )
  } else ""

  paste0(
    # --- Grounding ---
    "Answer the question using ONLY the information in the context below.\n",
    "Do not use any knowledge from outside the provided context.\n",
    # --- Citation ---
    "Begin your answer with: 'According to [document name]...' ",
    "where [document name] is the filename of the most relevant source.\n",
    # --- Fallback ---
    "If the answer is not in the context, say exactly: ",
    "'I cannot answer this from the provided documents.'\n",
    # --- Style ---
    "Keep your answer to 3 sentences or fewer unless a list is more appropriate.\n",
    "Do not mention the context, passages, or how you found the answer.\n\n",
    # --- Confidence note (conditional) ---
    confidence_note,
    # --- Context ---
    "Context:\n\n", context, "\n\n",
    # --- Question ---
    "Question: ", question, "\n\n",
    "Answer:"
  )
}
```

---

## top_k guidance

| top_k | When to use |
|---|---|
| 3 | Starting point. Good for focused, single-document questions. |
| 5 | Default target. Better for questions that span multiple sections. |
| 7 | Use if answers are consistently incomplete. Monitor prompt length. |
| >7 | Avoid — context window fills and LLM quality degrades. |

Increasing `top_k` also increases LLM response latency. Start at 5 and only increase if needed.

---

## Confidence flag

After `ragnar_retrieve_bm25()`, compute the confidence flag:

```r
LOW_CONFIDENCE_THRESHOLD <- 1.0

is_low_confidence <- is.null(top_chunks) ||
  nrow(top_chunks) == 0 ||
  max(top_chunks$metric_value, na.rm = TRUE) < LOW_CONFIDENCE_THRESHOLD
```

Pass `low_confidence = is_low_confidence` to `build_rag_prompt()`.
Return `is_low_confidence` to the Shiny UI so it can display the amber warning banner.

---

## Evaluating answer quality

Test the pipeline against these three question categories before the demo:

### 1. Direct lookup (tests precision)
Questions with a specific, findable answer in one document:
- "What is the eligibility threshold for housing support?"
- "How many days notice is required for flexible working requests?"

**Good sign:** Answer cites the correct document, is under 3 sentences, is accurate.
**Bad sign:** Answer is long, vague, or mentions documents that aren't the right source.

### 2. Cross-document (tests retrieval breadth)
Questions that require content from more than one document:
- "How does the housing benefit policy interact with employment support guidance?"
- "What are the approval thresholds across both procurement categories?"

**Good sign:** Answer cites multiple documents. Source table shows chunks from different files.
**Bad sign:** Only one document cited; answer misses the cross-domain aspect.

### 3. Out-of-scope (tests fallback — critical for credibility)
Questions whose answer is not in any indexed document:
- "What is the population of London?"
- "Who is the current Prime Minister?"

**Good sign:** Answer is exactly "I cannot answer this from the provided documents."
**Bad sign:** Any other answer. This is a hallucination and must be fixed via prompt strengthening.

---

## Common prompt failures and fixes

| Symptom | Cause | Fix |
|---|---|---|
| LLM ignores the fallback and guesses | Grounding instruction too soft | Use absolute form: "ONLY the information in the context" |
| Answer doesn't cite a document name | Citation instruction missing or ignored | Move citation instruction to first line of prompt |
| Answer is too long | No length constraint | Add: "3 sentences or fewer unless a list is appropriate" |
| `assistantfinal` appears in output | Model includes chain-of-thought reasoning prefix | `parse_answer()` strips this — ensure it is called |
| Answer repeats the question | Model is being verbose | Add: "Do not repeat the question back" |
| Out-of-scope questions hallucinate | Fallback phrase not exact | Ensure `parse_answer()` and prompt use identical fallback text |
