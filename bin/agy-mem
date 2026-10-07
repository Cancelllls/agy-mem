#!/usr/bin/env python3
"""
agy-mem: Autonomous Memory, Observation Extraction, and Fast Recall Engine for Google Antigravity (agy).
Maintains a local SQLite FTS5 knowledge graph of all architectural decisions, bugfixes,
user preferences, tool actions, and code patterns across all sessions and projects.
"""

import os
import sys
import glob
import json
import sqlite3
import argparse
import re
import hashlib
from datetime import datetime, timezone

# ANSI Color Codes (Antigravity Theme: Teal, Gold, Slate)
TEAL = "\033[38;2;20;184;166m"
CYAN = TEAL
GOLD = "\033[38;2;229;193;88m"
GREEN = "\033[38;2;34;197;94m"
BLUE = "\033[38;2;59;130;246m"
PURPLE = "\033[38;2;168;85;247m"
GRAY = "\033[38;2;100;116;139m"
LIGHT = "\033[38;2;241;245;249m"
RED = "\033[38;2;239;68;68m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"

DB_DIR = os.path.expanduser("~/.gemini/antigravity-cli")
DB_PATH = os.path.join(DB_DIR, "memory.db")
BRAIN_DIR = os.path.join(DB_DIR, "brain")
DOCS_MEM_DIR = os.path.expanduser("~/.agents/memory")
SUMMARIES_DB = os.path.join(DB_DIR, "conversation_summaries.db")

PROJECT_PATTERNS = [
    (r"/Aya|/Islamic-App", "Aya"),
    (r"/Badil", "Badil"),
    (r"/jumpcut-android", "JumpCut"),
    (r"/Halal_Forex_Bot", "HalalForex"),
    (r"/email|cancellls\.com", "Email"),
    (r"/fun-with-kanji", "FunKanji"),
    (r"/\.gemini|/\.agents|/\.local/bin", "Antigravity"),
]

TYPE_PATTERNS = [
    (r"\b(fix|bug|error|timeout|kill|killed|fail|failed|crash|broken|issue)\b", "bugfix"),
    (r"\b(architect|database|schema|fts5|engine|pipeline|workflow|model|plugin)\b", "architecture"),
    (r"\b(rule|prefer|always|never|standard|policy|guideline|ponytail)\b", "preference"),
    (r"\b(perf|benchmark|optim|speed|latency|cache|fast)\b", "pattern"),
    (r"\b(milestone|release|launch|v\d+\.\d+)\b", "milestone"),
]

def init_db(conn):
    cur = conn.cursor()
    cur.execute("PRAGMA journal_mode = WAL;")
    cur.execute("PRAGMA synchronous = NORMAL;")
    cur.execute("PRAGMA foreign_keys = ON;")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        source_id TEXT NOT NULL,
        project TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        narrative TEXT,
        facts TEXT,
        concepts TEXT,
        files_read TEXT,
        files_modified TEXT,
        created_at TEXT NOT NULL,
        created_at_epoch INTEGER NOT NULL,
        content_hash TEXT UNIQUE
    );
    """)

    cur.execute("CREATE INDEX IF NOT EXISTS idx_obs_project ON observations(project);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_obs_type ON observations(type);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_obs_created ON observations(created_at_epoch DESC);")

    # SQLite FTS5 Full-Text Index
    cur.execute("""
    CREATE VIRTUAL TABLE IF NOT EXISTS observations_fts USING fts5(
        title,
        narrative,
        facts,
        concepts,
        project,
        content='observations',
        content_rowid='id'
    );
    """)

    # Triggers for automatic FTS indexing
    cur.execute("""
    CREATE TRIGGER IF NOT EXISTS obs_ai AFTER INSERT ON observations BEGIN
        INSERT INTO observations_fts(rowid, title, narrative, facts, concepts, project)
        VALUES (new.id, new.title, new.narrative, new.facts, new.concepts, new.project);
    END;
    """)

    cur.execute("""
    CREATE TRIGGER IF NOT EXISTS obs_ad AFTER DELETE ON observations BEGIN
        INSERT INTO observations_fts(observations_fts, rowid, title, narrative, facts, concepts, project)
        VALUES('delete', old.id, old.title, old.narrative, old.facts, old.concepts, old.project);
    END;
    """)

    cur.execute("""
    CREATE TRIGGER IF NOT EXISTS obs_au AFTER UPDATE ON observations BEGIN
        INSERT INTO observations_fts(observations_fts, rowid, title, narrative, facts, concepts, project)
        VALUES('delete', old.id, old.title, old.narrative, old.facts, old.concepts, old.project);
        INSERT INTO observations_fts(rowid, title, narrative, facts, concepts, project)
        VALUES (new.id, new.title, new.narrative, new.facts, new.concepts, new.project);
    END;
    """)

    # Sync state tracker for incremental scans
    cur.execute("""
    CREATE TABLE IF NOT EXISTS sync_state (
        source_id TEXT PRIMARY KEY,
        last_processed_line INTEGER DEFAULT 0,
        last_mtime REAL DEFAULT 0,
        updated_at TEXT
    );
    """)
    conn.commit()

def detect_project(files, text=""):
    combined = " ".join(files) + " " + text
    for pattern, name in PROJECT_PATTERNS:
        if re.search(pattern, combined, re.IGNORECASE):
            return name
    return "General"

def detect_type(text):
    text_lower = text.lower()
    for pattern, name in TYPE_PATTERNS:
        if re.search(pattern, text_lower):
            return name
    return "feature"

def clean_request(raw):
    raw = re.sub(r"<[^>]+>", "", raw).strip()
    lines = [l.strip() for l in raw.split("\n") if l.strip()]
    if not lines:
        return "Task Execution"
    first = lines[0]
    first = re.sub(r"^[\s#*\->]+", "", first)
    return first[:80] if len(first) > 80 else first

def extract_concepts(text, files):
    words = set(re.findall(r"\b[a-zA-Z0-9_\-]{3,20}\b", text.lower()))
    stop = {
        "the", "and", "for", "that", "with", "this", "from", "have", "are", "was",
        "were", "what", "can", "you", "how", "why", "its", "not", "did", "run",
        "all", "out", "new", "get", "set", "use", "now", "see", "add", "make"
    }
    tags = [w for w in words if w not in stop]
    for f in files:
        base = f.split("/")[-1].split(".")[0]
        if len(base) > 2 and base.lower() not in stop:
            tags.append(base.lower())
    return ", ".join(sorted(set(tags))[:10])

def sync_markdown_docs(conn):
    """Indexes baseline structured knowledge from ~/.agents/memory/*.md."""
    if not os.path.exists(DOCS_MEM_DIR):
        return 0

    cur = conn.cursor()
    files = glob.glob(os.path.join(DOCS_MEM_DIR, "*.md"))
    added = 0

    for fpath in files:
        fname = os.path.basename(fpath)
        try:
            mtime = os.path.getmtime(fpath)
            cur.execute("SELECT last_mtime FROM sync_state WHERE source_id = ?;", (f"doc:{fname}",))
            row = cur.fetchone()
            if row and row[0] >= mtime:
                continue

            with open(fpath, "r", errors="ignore") as f:
                content = f.read()

            sections = re.split(r"\n(?=##\s+)", content)
            for sec in sections:
                if not sec.strip() or sec.startswith("---"):
                    continue
                lines = sec.strip().split("\n")
                header = lines[0].replace("##", "").strip()
                body = "\n".join(lines[1:]).strip()
                if not body or len(body) < 20:
                    continue

                bullets = [l.strip() for l in lines[1:] if l.strip().startswith(("-", "*"))]
                facts = "\n".join(bullets[:8]) if bullets else body[:300]
                narrative = body[:600]

                proj = detect_project([], fname + " " + header)
                typ = detect_type(header + " " + body[:100])
                created_iso = datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat()
                epoch = int(mtime)

                chash = hashlib.sha256(f"doc:{fname}:{header}".encode()).hexdigest()
                concepts = extract_concepts(header + " " + facts, [fname])

                cur.execute("""
                INSERT INTO observations (
                    source, source_id, project, type, title, narrative, facts, concepts,
                    files_read, files_modified, created_at, created_at_epoch, content_hash
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(content_hash) DO UPDATE SET
                    narrative=excluded.narrative, facts=excluded.facts, concepts=excluded.concepts;
                """, (
                    "memory_doc", fname, proj, typ, header, narrative, facts, concepts,
                    fpath, "", created_iso, epoch, chash
                ))
                added += 1

            cur.execute("""
            INSERT INTO sync_state (source_id, last_processed_line, last_mtime, updated_at)
            VALUES (?, 0, ?, datetime('now'))
            ON CONFLICT(source_id) DO UPDATE SET last_mtime = excluded.last_mtime, updated_at = excluded.updated_at;
            """, (f"doc:{fname}", mtime))

        except Exception as e:
            continue

    conn.commit()
    return added

def sync_transcripts(conn, force=False, target_session=None):
    """Scans Antigravity transcript logs and indexes turn-by-turn observations."""
    if not os.path.exists(BRAIN_DIR):
        return 0

    cur = conn.cursor()
    pattern = os.path.join(BRAIN_DIR, "*", ".system_generated", "logs", "transcript.jsonl")
    transcripts = glob.glob(pattern)
    transcripts.sort(key=os.path.getmtime, reverse=True)

    total_added = 0

    for tpath in transcripts:
        cid = tpath.split("/")[-4]
        if target_session and cid != target_session:
            continue

        try:
            mtime = os.path.getmtime(tpath)
            cur.execute("SELECT last_processed_line, last_mtime FROM sync_state WHERE source_id = ?;", (cid,))
            row = cur.fetchone()
            last_line = 0 if force or not row else row[0]
            if not force and row and row[1] >= mtime:
                continue

            current_turn = None
            turns = []
            line_count = 0

            with open(tpath, "r", errors="ignore") as f:
                for idx, line in enumerate(f):
                    line_count = idx + 1
                    if idx < last_line:
                        continue

                    try:
                        data = json.loads(line)
                    except Exception:
                        continue

                    t = data.get("type")
                    if t == "USER_INPUT":
                        if current_turn and (current_turn["files_modified"] or current_turn["tools"]):
                            turns.append(current_turn)
                        raw = data.get("content", "")
                        match = re.search(r"<USER_REQUEST>(.*?)</USER_REQUEST>", raw, re.DOTALL)
                        req = match.group(1).strip() if match else raw.strip()
                        current_turn = {
                            "start_idx": idx,
                            "created_at": data.get("created_at", datetime.now(timezone.utc).isoformat()),
                            "request": req,
                            "tools": [],
                            "files_modified": set(),
                            "files_read": set(),
                            "commands": [],
                            "assistant_summary": ""
                        }
                    elif current_turn is not None and t == "PLANNER_RESPONSE":
                        for tc in data.get("tool_calls", []):
                            name = tc.get("name")
                            args = tc.get("args", {})
                            current_turn["tools"].append(name)
                            if name in ("replace_file_content", "write_to_file"):
                                tf = args.get("TargetFile")
                                if tf:
                                    current_turn["files_modified"].add(str(tf).strip("\"'"))
                            elif name in ("view_file", "read_resource"):
                                ap = args.get("AbsolutePath") or args.get("Uri")
                                if ap:
                                    current_turn["files_read"].add(str(ap).strip("\"'"))
                            elif name == "run_command":
                                cmd = args.get("CommandLine")
                                if cmd:
                                    current_turn["commands"].append(str(cmd).strip("\"'")[:120])
                        if data.get("content"):
                            current_turn["assistant_summary"] = data.get("content")

            if current_turn and (current_turn["files_modified"] or current_turn["tools"]):
                turns.append(current_turn)

            for turn in turns:
                files_mod_list = sorted(list(turn["files_modified"]))
                files_read_list = sorted(list(turn["files_read"]))
                all_files = files_mod_list + files_read_list

                title = clean_request(turn["request"])
                if len(title) < 5 and files_mod_list:
                    title = f"Updated {os.path.basename(files_mod_list[0])}"

                proj = detect_project(all_files, turn["request"])
                typ = detect_type(turn["request"] + " " + turn["assistant_summary"][:300])

                facts_list = []
                for fm in files_mod_list[:4]:
                    facts_list.append(f"• Modified: {fm}")
                for cmd in turn["commands"][:3]:
                    facts_list.append(f"• Executed: {cmd}")
                facts = "\n".join(facts_list)

                summary_clean = re.sub(r"```.*?```", "[code block]", turn["assistant_summary"], flags=re.DOTALL)
                summary_clean = re.sub(r"<[^>]+>", "", summary_clean).strip()
                narrative = summary_clean[:500] if summary_clean else f"Action performed in response to: {title}"

                concepts = extract_concepts(title + " " + narrative, all_files)
                created_iso = turn["created_at"]
                try:
                    epoch = int(datetime.fromisoformat(created_iso.replace("Z", "+00:00")).timestamp())
                except Exception:
                    epoch = int(datetime.now().timestamp())

                chash = hashlib.sha256(f"conv:{cid}:{turn['start_idx']}:{title}".encode()).hexdigest()

                cur.execute("""
                INSERT INTO observations (
                    source, source_id, project, type, title, narrative, facts, concepts,
                    files_read, files_modified, created_at, created_at_epoch, content_hash
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(content_hash) DO NOTHING;
                """, (
                    "conversation", cid, proj, typ, title, narrative, facts, concepts,
                    ", ".join(files_read_list[:10]), ", ".join(files_mod_list[:10]),
                    created_iso, epoch, chash
                ))
                if cur.rowcount > 0:
                    total_added += 1

            cur.execute("""
            INSERT INTO sync_state (source_id, last_processed_line, last_mtime, updated_at)
            VALUES (?, ?, ?, datetime('now'))
            ON CONFLICT(source_id) DO UPDATE SET
                last_processed_line = excluded.last_processed_line,
                last_mtime = excluded.last_mtime,
                updated_at = excluded.updated_at;
            """, (cid, line_count, mtime))

        except Exception as e:
            continue

    conn.commit()
    return total_added

def search_memories(conn, query, project=None, obs_type=None, limit=10):
    """Executes FTS5 query with BM25 ranking and renders high-visibility cards."""
    cur = conn.cursor()

    # Clean query for FTS5 syntax
    sanitized = re.sub(r"[^\w\s\-]", " ", query).strip()
    if not sanitized:
        sanitized = query.strip()

    sql = """
    SELECT
        o.id, o.project, o.type, o.title, o.narrative, o.facts,
        o.files_modified, o.created_at, o.source, o.source_id,
        bm25(observations_fts) as rank
    FROM observations_fts f
    JOIN observations o ON o.id = f.rowid
    WHERE observations_fts MATCH ?
    """
    params = [sanitized]

    if project:
        sql += " AND o.project = ?"
        params.append(project)
    if obs_type:
        sql += " AND o.type = ?"
        params.append(obs_type)

    sql += " ORDER BY rank ASC LIMIT ?;"
    params.append(limit)

    try:
        cur.execute(sql, params)
        rows = cur.fetchall()
    except sqlite3.OperationalError:
        # Fallback to simple LIKE if MATCH syntax fails
        sql_like = """
        SELECT id, project, type, title, narrative, facts, files_modified, created_at, source, source_id, 0.0
        FROM observations
        WHERE title LIKE ? OR narrative LIKE ? OR facts LIKE ?
        ORDER BY created_at_epoch DESC LIMIT ?;
        """
        like_p = f"%{query}%"
        cur.execute(sql_like, (like_p, like_p, like_p, limit))
        rows = cur.fetchall()

    if not rows:
        print(f"\n{GRAY}No memory observations found matching:{RESET} {BOLD}{query}{RESET}\n")
        return

    print(f"\n{BOLD}{GOLD}🧠 Antigravity Memory Search:{RESET} {CYAN}\"{query}\"{RESET} ({len(rows)} results)\n")

    for row in rows:
        oid, proj, typ, title, narr, facts, fmod, created, src, src_id, rank = row

        type_color = {
            "bugfix": RED,
            "architecture": PURPLE,
            "preference": GOLD,
            "pattern": BLUE,
            "milestone": GREEN,
            "feature": TEAL
        }.get(typ, TEAL)

        date_str = created.split("T")[0] if "T" in created else created[:10]

        print(f"  {type_color}[{typ.upper()}]{RESET} {BOLD}{title}{RESET} {GRAY}· {proj} · {date_str}{RESET}")
        if narr:
            short_narr = narr[:180].replace("\n", " ")
            print(f"    {LIGHT}{short_narr}...{RESET}")
        if facts:
            for line in facts.split("\n")[:2]:
                if line.strip():
                    print(f"    {GRAY}{line.strip()}{RESET}")
        if fmod:
            print(f"    {TEAL}Files:{RESET} {DIM}{fmod[:100]}{RESET}")
        print()

def recall_memories(conn, query, project=None, limit=5):
    """Outputs compact Markdown context formatted for agent prompt ingestion."""
    cur = conn.cursor()
    sanitized = re.sub(r"[^\w\s\-]", " ", query).strip()

    sql = """
    SELECT o.project, o.type, o.title, o.narrative, o.facts, o.files_modified, o.created_at
    FROM observations_fts f
    JOIN observations o ON o.id = f.rowid
    WHERE observations_fts MATCH ?
    """
    params = [sanitized]
    if project:
        sql += " AND o.project = ?"
        params.append(project)

    sql += " ORDER BY bm25(observations_fts) ASC LIMIT ?;"
    params.append(limit)

    try:
        cur.execute(sql, params)
        rows = cur.fetchall()
    except Exception:
        rows = []

    if not rows:
        print(f"<!-- agy-mem: No prior memory found for query: {query} -->")
        return

    print("<recalled_memory>")
    print(f"<!-- Historical decisions, bugfixes, and architecture matching: {query} -->\n")
    for proj, typ, title, narr, facts, fmod, created in rows:
        print(f"### [{proj}] {title} ({typ})")
        if narr:
            print(narr)
        if facts:
            print(facts)
        if fmod:
            print(f"**Associated Files:** `{fmod}`")
        print()
    print("</recalled_memory>")

def show_status(conn):
    """Displays comprehensive statistics on indexed memory."""
    cur = conn.cursor()
    cur.execute("SELECT count(*) FROM observations;")
    total = cur.fetchone()[0]

    cur.execute("SELECT project, count(*) FROM observations GROUP BY project ORDER BY count(*) DESC;")
    by_proj = cur.fetchall()

    cur.execute("SELECT type, count(*) FROM observations GROUP BY type ORDER BY count(*) DESC;")
    by_type = cur.fetchall()

    db_size = os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else 0
    size_str = f"{db_size / (1024*1024):.2f} MB" if db_size > 1024*1024 else f"{db_size / 1024:.1f} KB"

    cur.execute("SELECT count(*) FROM sync_state;")
    synced_sessions = cur.fetchone()[0]

    print(f"\n{BOLD}{GOLD}🧠 Antigravity Memory Engine (agy-mem) Status{RESET}\n")
    print(f"  {CYAN}Total Observations:{RESET}  {BOLD}{total:,}{RESET}")
    print(f"  {CYAN}Synced Sessions:{RESET}     {synced_sessions}")
    print(f"  {CYAN}Database Size:{RESET}       {size_str} ({DB_PATH})")
    print()

    print(f"  {BOLD}Observations by Project:{RESET}")
    for proj, count in by_proj:
        bar = "■" * min(20, max(1, int((count / (total or 1)) * 20)))
        print(f"    {TEAL}{proj:<14}{RESET} {count:>5} {GRAY}{bar}{RESET}")
    print()

    print(f"  {BOLD}Observations by Type:{RESET}")
    for typ, count in by_type:
        bar = "■" * min(20, max(1, int((count / (total or 1)) * 20)))
        print(f"    {PURPLE}{typ:<14}{RESET} {count:>5} {GRAY}{bar}{RESET}")
def show_timeline(conn, earliest=False, project=None, limit=10):
    cur = conn.cursor()
    order = "ASC" if earliest else "DESC"
    sql = "SELECT id, project, type, title, created_at, substr(narrative, 1, 140) FROM observations"
    params = []
    if project:
        sql += " WHERE project = ?"
        params.append(project)
    sql += f" ORDER BY created_at_epoch {order} LIMIT ?;"
    params.append(limit)
    cur.execute(sql, params)
    rows = cur.fetchall()

    header = "Origin / Earliest First" if earliest else "Latest First"
    print(f"\n{BOLD}{GOLD}⏱️ Antigravity Memory Timeline ({header}):{RESET}\n")
    for oid, proj, typ, title, created, snip in rows:
        type_color = {
            "bugfix": RED, "architecture": PURPLE, "preference": GOLD,
            "pattern": BLUE, "milestone": GREEN, "feature": TEAL
        }.get(typ, TEAL)
        date_str = created.split("T")[0] if "T" in created else created[:10]
        time_str = created.split("T")[1][:8] if "T" in created else ""
        print(f"  {type_color}[{typ.upper()}]{RESET} {BOLD}{title}{RESET} {GRAY}· {proj} · {date_str} {time_str}{RESET}")
        if snip:
            print(f"    {LIGHT}{snip.strip().replace(chr(10), ' ')}...{RESET}")
        print()

def handle_tool_call(conn, name, args):
    cur = conn.cursor()
    if name == "search":
        q = args.get("query", "").strip()
        proj = args.get("project")
        typ = args.get("type")
        limit = int(args.get("limit", 10))

        sanitized = re.sub(r"[^\w\s\-]", " ", q).strip() or q
        sql = """
        SELECT o.id, o.project, o.type, o.title, o.created_at, substr(o.narrative, 1, 250), bm25(observations_fts) as rank
        FROM observations_fts f
        JOIN observations o ON o.id = f.rowid
        WHERE observations_fts MATCH ?
        """
        params = [sanitized]
        if proj:
            sql += " AND o.project = ?"
            params.append(proj)
        if typ:
            sql += " AND o.type = ?"
            params.append(typ)
        sql += " ORDER BY rank ASC LIMIT ?;"
        params.append(limit)

        try:
            cur.execute(sql, params)
            rows = cur.fetchall()
        except Exception:
            sql_like = """
            SELECT id, project, type, title, created_at, substr(narrative, 1, 250), 0.0
            FROM observations
            WHERE title LIKE ? OR narrative LIKE ?
            ORDER BY created_at_epoch DESC LIMIT ?;
            """
            p = f"%{q}%"
            cur.execute(sql_like, (p, p, limit))
            rows = cur.fetchall()

        results = []
        for r in rows:
            results.append({
                "id": r[0],
                "project": r[1],
                "type": r[2],
                "title": r[3],
                "created_at": r[4],
                "snippet": r[5]
            })
        return json.dumps(results, indent=2)

    elif name == "get_observations":
        ids = args.get("ids", [])
        if not ids:
            return json.dumps([])
        placeholders = ",".join("?" for _ in ids)
        sql = f"""
        SELECT id, project, type, title, narrative, facts, concepts, files_modified, files_read, created_at, source, source_id
        FROM observations WHERE id IN ({placeholders});
        """
        cur.execute(sql, ids)
        rows = cur.fetchall()
        results = []
        for r in rows:
            results.append({
                "id": r[0],
                "project": r[1],
                "type": r[2],
                "title": r[3],
                "narrative": r[4],
                "facts": r[5],
                "concepts": r[6],
                "files_modified": r[7],
                "files_read": r[8],
                "created_at": r[9],
                "source": r[10],
                "source_id": r[11]
            })
        return json.dumps(results, indent=2)

    elif name == "recall":
        q = args.get("query", "").strip()
        proj = args.get("project")
        limit = int(args.get("limit", 5))
        sanitized = re.sub(r"[^\w\s\-]", " ", q).strip() or q
        sql = """
        SELECT o.project, o.type, o.title, o.narrative, o.facts, o.files_modified, o.created_at
        FROM observations_fts f
        JOIN observations o ON o.id = f.rowid
        WHERE observations_fts MATCH ?
        """
        params = [sanitized]
        if proj:
            sql += " AND o.project = ?"
            params.append(proj)
        sql += " ORDER BY bm25(observations_fts) ASC LIMIT ?;"
        params.append(limit)
        try:
            cur.execute(sql, params)
            rows = cur.fetchall()
        except Exception:
            rows = []

        if not rows:
            return f"<!-- agy-mem: No prior memory found for: {q} -->"

        out = ["<recalled_memory>", f"<!-- Historical decisions, bugfixes, and architecture matching: {q} -->\n"]
        for p, t, title, narr, facts, fmod, created in rows:
            out.append(f"### [{p}] {title} ({t})")
            if narr:
                out.append(narr)
            if facts:
                out.append(facts)
            if fmod:
                out.append(f"**Associated Files:** `{fmod}`")
            out.append("")
        out.append("</recalled_memory>")
        return "\n".join(out)

    elif name == "timeline":
        proj = args.get("project")
        limit = int(args.get("limit", 15))
        sql = "SELECT id, project, type, title, created_at, substr(narrative, 1, 150) FROM observations"
        params = []
        if proj:
            sql += " WHERE project = ?"
            params.append(proj)
        sql += " ORDER BY created_at_epoch DESC LIMIT ?;"
        params.append(limit)
        cur.execute(sql, params)
        rows = cur.fetchall()
        events = []
        for r in rows:
            events.append({
                "id": r[0],
                "project": r[1],
                "type": r[2],
                "title": r[3],
                "created_at": r[4],
                "summary": r[5]
            })
        return json.dumps(events, indent=2)

    elif name == "add_observation":
        proj = args["project"]
        typ = args.get("type", "architecture")
        title = args["title"]
        narrative = args["narrative"]
        facts = args.get("facts", "")
        concepts = args.get("concepts", "")
        now_iso = datetime.now(timezone.utc).isoformat()
        epoch = int(datetime.now().timestamp())
        chash = hashlib.sha256(f"mcp:{proj}:{title}:{now_iso}".encode()).hexdigest()
        cur.execute("""
        INSERT INTO observations (
            source, source_id, project, type, title, narrative, facts, concepts,
            files_read, files_modified, created_at, created_at_epoch, content_hash
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, (
            "mcp", "agent", proj, typ, title, narrative, facts, concepts, "", "", now_iso, epoch, chash
        ))
        conn.commit()
        return json.dumps({"success": True, "id": cur.lastrowid, "title": title})

    elif name == "sync":
        full = args.get("full", False)
        docs_added = sync_markdown_docs(conn)
        trans_added = sync_transcripts(conn, force=full)
        return json.dumps({"success": True, "docs_added": docs_added, "transcripts_added": trans_added})

    else:
        raise ValueError(f"Unknown tool: {name}")

def run_mcp_server(conn):
    """Runs a standard JSON-RPC 2.0 stdio MCP server for Antigravity & Claude."""
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue

        msg_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {})

        if method == "initialize":
            resp = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {
                        "tools": {"listChanged": False}
                    },
                    "serverInfo": {
                        "name": "agy-mem",
                        "version": "1.0.0"
                    }
                }
            }
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()

        elif method == "notifications/initialized":
            pass

        elif method == "ping":
            resp = {"jsonrpc": "2.0", "id": msg_id, "result": {}}
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()

        elif method == "tools/list":
            tools = [
                {
                    "name": "search",
                    "description": "Search memory observations using full-text search with BM25 ranking (matches claude-mem search).",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "query": {"type": "string", "description": "Search query keywords or phrase"},
                            "project": {"type": "string", "description": "Filter by project name (Aya, Badil, JumpCut, HalalForex, Email, FunKanji, Antigravity)"},
                            "type": {"type": "string", "description": "Filter by observation type (architecture, bugfix, feature, preference, pattern)"},
                            "limit": {"type": "number", "description": "Maximum number of results to return (default: 10)"}
                        },
                        "required": ["query"]
                    }
                },
                {
                    "name": "get_observations",
                    "description": "Fetch full details for observation IDs returned by search (matches claude-mem get_observations).",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "ids": {
                                "type": "array",
                                "items": {"type": "integer"},
                                "description": "List of observation IDs to fetch"
                            }
                        },
                        "required": ["ids"]
                    }
                },
                {
                    "name": "recall",
                    "description": "High-level contextual memory retrieval formatted as markdown for direct agent reasoning (matches claude-mem smart_search).",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "query": {"type": "string", "description": "Topic or concept to recall"},
                            "project": {"type": "string", "description": "Filter by project name"},
                            "limit": {"type": "number", "description": "Number of memory items to return (default: 5)"}
                        },
                        "required": ["query"]
                    }
                },
                {
                    "name": "timeline",
                    "description": "Get chronological timeline of historical milestones, decisions, and bugfixes.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "project": {"type": "string", "description": "Filter by project name (optional)"},
                            "limit": {"type": "number", "description": "Number of timeline events (default: 15)"}
                        }
                    }
                },
                {
                    "name": "add_observation",
                    "description": "Store a new architectural decision, bugfix, or user preference into memory.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "project": {"type": "string", "description": "Project name (e.g. Aya, Badil, JumpCut)"},
                            "type": {"type": "string", "enum": ["architecture", "bugfix", "feature", "preference", "pattern"], "description": "Observation category"},
                            "title": {"type": "string", "description": "Short, clear title for the memory"},
                            "narrative": {"type": "string", "description": "Detailed description of the decision, fix, or preference"},
                            "facts": {"type": "string", "description": "Key bullet points or concrete facts"},
                            "concepts": {"type": "string", "description": "Comma-separated concept tags"}
                        },
                        "required": ["project", "type", "title", "narrative"]
                    }
                },
                {
                    "name": "sync",
                    "description": "Trigger an incremental sync to extract newly created observations from recent conversations.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "full": {"type": "boolean", "description": "Force full rescan instead of incremental"}
                        }
                    }
                }
            ]
            resp = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {"tools": tools}
            }
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()

        elif method == "tools/call":
            tool_name = params.get("name")
            args = params.get("arguments", {})
            try:
                res_text = handle_tool_call(conn, tool_name, args)
                resp = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "content": [
                            {"type": "text", "text": res_text}
                        ]
                    }
                }
            except Exception as e:
                resp = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "isError": True,
                    "result": {
                        "content": [
                            {"type": "text", "text": f"Error executing {tool_name}: {str(e)}"}
                        ]
                    }
                }
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()

def main():
    parser = argparse.ArgumentParser(description="Antigravity Autonomous Memory & Fast Recall Engine")
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # sync
    sync_p = subparsers.add_parser("sync", help="Synchronize conversations and memory docs into database")
    sync_p.add_argument("--full", action="store_true", help="Force full rescan of all sessions")
    sync_p.add_argument("--session", type=str, help="Sync specific conversation ID only")

    # search
    search_p = subparsers.add_parser("search", help="Search memory observations via FTS5")
    search_p.add_argument("query", help="Search keywords or phrase")
    search_p.add_argument("-p", "--project", help="Filter by project name")
    search_p.add_argument("-t", "--type", help="Filter by observation type (bugfix, architecture, etc.)")
    search_p.add_argument("-n", "--limit", type=int, default=8, help="Max results (default: 8)")

    # recall
    recall_p = subparsers.add_parser("recall", help="Recall memory as Markdown context for agent ingestion")
    recall_p.add_argument("query", help="Recall query")
    recall_p.add_argument("-p", "--project", help="Filter by project name")
    recall_p.add_argument("-n", "--limit", type=int, default=5, help="Max results (default: 5)")

    # add
    add_p = subparsers.add_parser("add", help="Manually add a memory observation")
    add_p.add_argument("-p", "--project", required=True, help="Project name")
    add_p.add_argument("-t", "--type", default="architecture", help="Type (architecture, bugfix, preference, etc.)")
    add_p.add_argument("--title", required=True, help="Short title")
    add_p.add_argument("--narrative", required=True, help="Detailed explanation")
    add_p.add_argument("--facts", default="", help="Bullet points or key facts")
    add_p.add_argument("--concepts", default="", help="Comma-separated tags")

    # observe
    subparsers.add_parser("observe", help="Incremental sync on active session only")

    # timeline
    timeline_p = subparsers.add_parser("timeline", help="Display chronological timeline of memories")
    timeline_p.add_argument("--earliest", action="store_true", help="Start from the very first memory (oldest to newest)")
    timeline_p.add_argument("-p", "--project", help="Filter by project name")
    timeline_p.add_argument("-n", "--limit", type=int, default=10, help="Number of records to show")

    # mcp
    subparsers.add_parser("mcp", help="Run stdio JSON-RPC MCP server for Antigravity & Claude")

    args = parser.parse_args()

    os.makedirs(DB_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    init_db(conn)

    if args.command == "mcp":
        run_mcp_server(conn)
        return

    if args.command == "sync":
        print(f"{TEAL}Syncing baseline documentation knowledge...{RESET}")
        docs_added = sync_markdown_docs(conn)
        print(f"{TEAL}Syncing conversation transcripts...{RESET}")
        trans_added = sync_transcripts(conn, force=args.full, target_session=args.session)
        print(f"{GREEN}✓ Sync completed:{RESET} {docs_added} doc sections, {trans_added} conversation observations added.")
        show_status(conn)

    elif args.command == "search":
        search_memories(conn, args.query, project=args.project, obs_type=args.type, limit=args.limit)

    elif args.command == "recall":
        recall_memories(conn, args.query, project=args.project, limit=args.limit)

    elif args.command == "add":
        now_iso = datetime.now(timezone.utc).isoformat()
        epoch = int(datetime.now().timestamp())
        chash = hashlib.sha256(f"manual:{args.project}:{args.title}:{now_iso}".encode()).hexdigest()
        cur = conn.cursor()
        cur.execute("""
        INSERT INTO observations (
            source, source_id, project, type, title, narrative, facts, concepts,
            files_read, files_modified, created_at, created_at_epoch, content_hash
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, (
            "manual", "cli", args.project, args.type, args.title, args.narrative,
            args.facts, args.concepts, "", "", now_iso, epoch, chash
        ))
        conn.commit()
        print(f"{GREEN}✓ Memory observation recorded successfully:{RESET} {BOLD}{args.title}{RESET}")

    elif args.command == "observe":
        # Check active session quickly
        added = sync_transcripts(conn, force=False)
        print(f"✓ Observation check complete: {added} new turns captured.")

    elif args.command == "timeline":
        show_timeline(conn, earliest=args.earliest, project=args.project, limit=args.limit)

    elif args.command == "status" or not args.command:
        show_status(conn)

    conn.close()

if __name__ == "__main__":
    main()
