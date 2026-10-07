---
name: recall
description: >
  Retrieves historical architectural decisions, bugfixes, user preferences,
  and code patterns across all sessions and projects using agy-mem.
  Trigger: /recall, /mem.
---

# /recall & /mem

Searches and retrieves past memory observations from the local SQLite FTS5 database (`~/.gemini/antigravity-cli/memory.db`).

### Usage
- For human-readable search cards:
  ```bash
  agy-mem search "<query>"
  ```
- To inject past context into agent prompt:
  ```bash
  agy-mem recall "<query>"
  ```
- To inspect database health and statistics:
  ```bash
  agy-mem status
  ```
- To manually record a new memory node:
  ```bash
  agy-mem add --project <Project> --type <architecture|bugfix|preference> --title "<Title>" --narrative "<Description>"
  ```
