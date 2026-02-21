
## 2026-02-21
### Fixed
- Fixed empty outputs in CLaRa Agentic Search interface caused by hardcoded placeholder LLM prompt texts ("User query context text...").
- Injected `generateAgenticContextString(limit:)` via `DiverDataStore` into `AgenticSearchService` and `EdgeNodeService` to fetch `.transcription` and `.summary` strings directly from recent `ProcessedItem` models.
- Resolved TLS parsing and empty Data unpacking errors in macOS distributed actor routing mechanisms.
