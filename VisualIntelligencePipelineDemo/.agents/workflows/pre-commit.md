---
description: Update all documentation files before committing to GitHub
---

# Pre-Commit Documentation Workflow

Run this checklist before every commit to ensure all docs stay current.

// turbo-all

## 1. Gather current counts

```bash
# Service count
find DiverKit/Sources/DiverKit/Services -name '*.swift' | wc -l

# Protocol count
find DiverKit/Sources/DiverKit/Protocols -name '*.swift' | wc -l

# View count
find VisualIntelligencePipeline/VisualIntelligencePipeline/View -name '*.swift' | wc -l

# Test file count
find DiverKit/Tests -name '*.swift' | wc -l
find VisualIntelligencePipeline/VisualIntelligencePipelineTests -name '*.swift' 2>/dev/null | wc -l

# Model count
find DiverKit/Sources/DiverKit/Models -name '*.swift' | wc -l
```

## 2. Update these files (in order)

### `changelog.md`
- Add a dated entry (`## YYYY-MM-DD`) at the top
- List all changes grouped by category (Features, Fixes, Refactoring, Documentation)
- Include file names for new/deleted files

### `GEMINI.md`
- Update service/protocol/view/test counts if changed
- Update Key Files section if files were added/removed/renamed
- Update development rules if new patterns were established
- Update Code Cleanliness section with new tech debt or resolved items

### `README.md`
- Update feature descriptions if user-facing behavior changed
- Update architecture diagram if services/models changed
- Update build instructions if dependencies changed

### `spec.md`
- Update if the change affects planned features or architecture

### `Documentation/APP_SUMMARY.md`
- Update if the change affects user-facing features

### `Documentation/analysis.md`
- Update if the change affects technical architecture

### `Documentation/BETA_REVIEW_NOTES.md`
- Update if the change affects App Store review considerations

### HTML wiki (`Documentation/wiki/`)
- Update relevant wiki pages if features or architecture changed
- Update stat counts in wiki pages

## 3. Verify

```bash
# Check no stale counts remain
grep -rn 'XX services\|XX protocols\|XX views\|XX test' GEMINI.md README.md Documentation/
```

## 4. Commit

```bash
git add -A
git status  # Review staged changes
git commit -m "descriptive message"
```
