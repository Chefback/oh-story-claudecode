#!/usr/bin/env bash
# aggregate-review.sh — Pass 2 cumulative-pattern aggregator for /story-review v1.1.0.
#
# Reads every CHAPTER_META JSON in .omc/review-cache/*.json, computes pure-
# arithmetic cross-chapter statistics, prints a "Cumulative Patterns" section
# suitable for embedding into the Phase 4 report.
#
# NO LLM CALL. NO PROSE LOADED. Purely structured-data aggregation.
#
# Usage:
#   bash scripts/aggregate-review.sh                        # default cache dir
#   bash scripts/aggregate-review.sh --cache <dir>
#   bash scripts/aggregate-review.sh --json                 # emit JSON instead of markdown
#
# Exit codes:
#   0 — aggregation completed (may report 0 chapters if cache empty)
#   1 — invalid CHAPTER_META in cache (schema_version mismatch or required field missing)

set -euo pipefail

CACHE_DIR=".omc/review-cache"
EMIT_FORMAT="markdown"

while [ $# -gt 0 ]; do
  case "$1" in
    --cache) CACHE_DIR="$2"; shift 2 ;;
    --json) EMIT_FORMAT="json"; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "[aggregate-review] unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$CACHE_DIR" ]; then
  if [ "$EMIT_FORMAT" = "json" ]; then
    echo '{"chapter_count": 0, "note": "cache dir missing"}'
  else
    echo "## Cumulative Patterns"
    echo
    echo "_Cache dir \`$CACHE_DIR\` not found. Run Pass 2A first._"
  fi
  exit 0
fi

python3 - "$CACHE_DIR" "$EMIT_FORMAT" <<'PY'
import json
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

cache_dir = Path(sys.argv[1])
emit = sys.argv[2]

metas = []
parse_errors = []
for jf in sorted(cache_dir.glob("*.json")):
    try:
        with open(jf, encoding="utf-8") as f:
            m = json.load(f)
        if m.get("schema_version") != "1.0":
            parse_errors.append(f"{jf.name}: schema_version != '1.0'")
            continue
        if not all(k in m for k in ("chapter_id", "verdict", "ai_grade")):
            parse_errors.append(f"{jf.name}: missing required fields")
            continue
        metas.append(m)
    except (json.JSONDecodeError, OSError) as e:
        parse_errors.append(f"{jf.name}: {e}")

if parse_errors:
    sys.stderr.write("[aggregate-review] parse errors:\n")
    for e in parse_errors:
        sys.stderr.write(f"  - {e}\n")
    sys.exit(1)

# Bucket per chapter — one chapter may have up to 3 CHAPTER_META rows
# (architect + character-designer + narrative-writer). Merge them per chapter_id.
per_chapter = defaultdict(list)
for m in metas:
    per_chapter[m["chapter_id"]].append(m)

chapter_count = len(per_chapter)
total_meta_rows = len(metas)

# Aggregate stats
ai_grade_counter = Counter()
banned_word_chapters = defaultdict(set)
body_word_total = Counter()
rhythm_tag_counter = Counter()
sentence_diversity_counter = Counter()
foreshadow_planted = defaultdict(set)
foreshadow_resolved = defaultdict(set)
pov_sequence = []
char_drift_chapters = []
verdict_counter = Counter()

for chapter_id, rows in per_chapter.items():
    # AI grade: prefer narrative-writer's (heaviest of any) — take max
    grades = [r.get("ai_grade", "light") for r in rows if r.get("ai_grade")]
    if grades:
        # rank light=0, medium=1, heavy=2
        rank = {"light": 0, "medium": 1, "heavy": 2}
        max_grade = max(grades, key=lambda g: rank.get(g, 0))
        ai_grade_counter[max_grade] += 1

    # Verdict: pessimistic merge — if any agent REJECTs, chapter REJECTs
    verdicts = [r.get("verdict") for r in rows if r.get("verdict")]
    if "REJECT" in verdicts:
        verdict_counter["REJECT"] += 1
    elif "CONCERNS" in verdicts:
        verdict_counter["CONCERNS"] += 1
    elif "APPROVE" in verdicts:
        verdict_counter["APPROVE"] += 1

    # Banned word reuse — per-chapter set of words
    for r in rows:
        for item in r.get("banned_words_found", []):
            banned_word_chapters[item["word"]].add(chapter_id)

    # Body word saturation — cumulative count
    for r in rows:
        for item in r.get("body_parts_used", []):
            body_word_total[item["word"]] += item["count"]

    # Rhythm tags
    for r in rows:
        for tag in r.get("rhythm_tags", []):
            rhythm_tag_counter[tag] += 1

    # Sentence diversity — use the narrative-writer one if available
    for r in rows:
        sd = r.get("sentence_pattern_diversity")
        if sd:
            sentence_diversity_counter[sd] += 1
            break

    # Foreshadow lifecycle
    for r in rows:
        for fid in r.get("foreshadow_planted", []):
            foreshadow_planted[fid].add(chapter_id)
        for fid in r.get("foreshadow_resolved", []):
            foreshadow_resolved[fid].add(chapter_id)

    # POV / drift
    for r in rows:
        pov = r.get("pov_character")
        if pov:
            pov_sequence.append((chapter_id, pov))
            break
    for r in rows:
        if r.get("char_drift_flag"):
            char_drift_chapters.append(chapter_id)
            break

# Compute cross-chapter signals
banned_reuse_findings = []
for word, chapters in banned_word_chapters.items():
    n = len(chapters)
    if chapter_count > 0 and n / chapter_count >= 0.4:
        banned_reuse_findings.append((word, n, chapter_count))

body_saturation_findings = []
for word, total in body_word_total.items():
    if total >= 15:  # arbitrary threshold across volume
        body_saturation_findings.append((word, total))

orphan_foreshadows = [
    (fid, sorted(chs)[0]) for fid, chs in foreshadow_planted.items()
    if fid not in foreshadow_resolved
]

# Rhythm uniformity: low diversity = suspicious
total_rhythm = sum(rhythm_tag_counter.values()) or 1
top_rhythm_pct = max(rhythm_tag_counter.values(), default=0) / total_rhythm
rhythm_uniform_warn = top_rhythm_pct > 0.6 and total_rhythm > 3

# Low sentence diversity ratio
low_sd_chapters = sentence_diversity_counter.get("low", 0)
low_sd_ratio = low_sd_chapters / chapter_count if chapter_count else 0
mechanical_warn = low_sd_ratio >= 0.3

# AI-heavy concentration
heavy_count = ai_grade_counter.get("heavy", 0)
heavy_ratio = heavy_count / chapter_count if chapter_count else 0
ai_heavy_warn = heavy_ratio >= 0.3

if emit == "json":
    out = {
        "chapter_count": chapter_count,
        "total_meta_rows": total_meta_rows,
        "verdict_distribution": dict(verdict_counter),
        "ai_grade_distribution": dict(ai_grade_counter),
        "ai_heavy_ratio": heavy_ratio,
        "ai_heavy_warning": ai_heavy_warn,
        "banned_word_reuse": [
            {"word": w, "chapter_count": n, "of_total": total}
            for (w, n, total) in banned_reuse_findings
        ],
        "body_word_saturation": [
            {"word": w, "total_count": t} for (w, t) in body_saturation_findings
        ],
        "rhythm_uniformity_warning": rhythm_uniform_warn,
        "top_rhythm_tag_pct": top_rhythm_pct,
        "sentence_diversity": dict(sentence_diversity_counter),
        "mechanical_warning": mechanical_warn,
        "low_diversity_ratio": low_sd_ratio,
        "orphan_foreshadows": [
            {"id": fid, "planted_in": ch} for (fid, ch) in orphan_foreshadows
        ],
        "pov_sequence_length": len(pov_sequence),
        "char_drift_chapters": char_drift_chapters,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    sys.exit(0)

# Markdown emission
print("## Cumulative Patterns")
print()
print(f"Aggregated from `{cache_dir}` — {chapter_count} chapter(s), {total_meta_rows} CHAPTER_META row(s).")
print(f"_Pure arithmetic on structured data; subjective gestalt requires manual prose review._")
print()

print("### Verdict distribution")
for v in ["APPROVE", "CONCERNS", "REJECT"]:
    n = verdict_counter.get(v, 0)
    print(f"- {v}: {n}")
print()

print("### AI taste distribution")
for g in ["light", "medium", "heavy"]:
    n = ai_grade_counter.get(g, 0)
    print(f"- {g}: {n}")
if ai_heavy_warn:
    print()
    print(f"**[S2-cumulative]** heavy AI-taste ratio = {heavy_ratio:.0%} ≥ 30% — review prose-craft baseline.")
print()

if banned_reuse_findings:
    print("### Banned word reuse (>= 40% of chapters)")
    for word, n, total in sorted(banned_reuse_findings, key=lambda x: -x[1]):
        print(f"- **[S2-cumulative]** `{word}` in {n}/{total} chapters")
    print()

if body_saturation_findings:
    print("### Body-part word saturation (cumulative >= 15)")
    for word, total in sorted(body_saturation_findings, key=lambda x: -x[1]):
        print(f"- **[S3-cumulative]** `{word}` total {total} uses")
    print()

if rhythm_uniform_warn or mechanical_warn:
    print("### Rhythm / pattern uniformity")
    if rhythm_uniform_warn:
        top_tag = rhythm_tag_counter.most_common(1)[0][0]
        print(f"- **[S2-cumulative]** rhythm tag `{top_tag}` dominates at {top_rhythm_pct:.0%} — pacing may be mechanical.")
    if mechanical_warn:
        print(f"- **[S2-cumulative]** low sentence diversity in {low_sd_chapters}/{chapter_count} chapters ({low_sd_ratio:.0%}) — SVO-loop AI tell suspected.")
    print()

if orphan_foreshadows:
    print("### Orphan foreshadows (planted, never resolved)")
    for fid, ch in sorted(orphan_foreshadows):
        print(f"- **[S4]** `{fid}` planted in chapter `{ch}`, no resolution found in cached chapters")
    print()

if char_drift_chapters:
    print("### Candidate character drift")
    print(f"- **[S3]** char_drift_flag set in chapters: {', '.join(sorted(char_drift_chapters))}")
    print(f"  Cross-reference with each character's 预期语言风格弧线 (角色档案) before treating as defect.")
    print()

print("_End of cumulative patterns._")
PY
