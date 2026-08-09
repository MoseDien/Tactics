#!/usr/bin/env python3
"""
Export the app's offline puzzle library from the Lichess SQLite database.

Produces the 11 JSON files the iOS app bundles:

  - 1000.json ... 1900.json : 1000 random puzzles per 100-point rating band
                              (rating in [lower, lower+100)), loaded in one
                              bulk pass on first launch.
  - rating_puzzles.json     : 100 puzzles spanning a broad rating range, used
                              by the Rating Assessment to set a baseline score.

Each file is an array of objects whose keys match the `ImportPuzzle` /
`Puzzle` Codable shape in the Swift sources (camelCase: ratingDeviation,
gameUrl, playCount, openingTags). Theme tags are filtered to the app's
`PuzzleTheme` enum raw values; unknown Lichess-only tags are dropped so the
files decode under both the lenient importer path and the strict `[Puzzle]`
assessment path.

Usage:
    python export_tier_puzzles.py \\
        ../data/source/lichess_puzzles.sqlite \\
        ../../DailyTactics/Resources
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

# Must match the `PuzzleTheme` enum raw values in
# DailyTactics/Sources/PuzzleKit/Puzzle.swift.
KNOWN_THEMES = {
    "fork",
    "pin",
    "skewer",
    "discoveredAttack",
    "sacrifice",
    "mate",
    "defensiveMove",
    "endgame",
    "advantage",
    "middlegame",
    "rookEndgame",
    "short",
}

TIER_LOWERS = range(1000, 2000, 100)  # 1000, 1100, ..., 1900
PER_TIER = 1000
ASSESSMENT_COUNT = 100

_SELECT = (
    "SELECT puzzle_id, fen, moves, rating, rating_deviation, popularity, "
    "play_count, themes, game_url, opening_tags "
    "FROM puzzles WHERE rating >= ? AND rating < ? ORDER BY RANDOM() LIMIT ?"
)


def row_to_puzzle(row: sqlite3.Row) -> dict:
    moves = row["moves"].split()
    themes = [t for t in row["themes"].split() if t in KNOWN_THEMES]
    return {
        "id": row["puzzle_id"],
        "fen": row["fen"],
        "moves": moves,
        "rating": row["rating"],
        "ratingDeviation": row["rating_deviation"],
        "popularity": row["popularity"],
        "playCount": row["play_count"],
        "themes": themes,
        "gameUrl": row["game_url"],
        "openingTags": row["opening_tags"].split(),
    }


def export_tier(conn: sqlite3.Connection, output_dir: Path, lower: int) -> tuple[int, Path]:
    rows = conn.execute(_SELECT, (lower, lower + 100, PER_TIER)).fetchall()
    puzzles = [row_to_puzzle(r) for r in rows if r["moves"].split()]
    path = output_dir / f"{lower}.json"
    path.write_text(json.dumps(puzzles, ensure_ascii=False))
    return len(puzzles), path


def export_assessment(conn: sqlite3.Connection, output_dir: Path) -> tuple[int, Path]:
    # Sample roughly evenly across rating buckets so the client-side
    # RatingAssessmentPlan has a real difficulty spread to bucket-pick from.
    bucket = max(1, ASSESSMENT_COUNT // 12)
    bands = range(400, 2801, 200)
    picked: list[sqlite3.Row] = []
    for lo in bands:
        rows = conn.execute(_SELECT, (lo, lo + 200, bucket)).fetchall()
        picked.extend(r for r in rows if r["moves"].split())
    puzzles = [row_to_puzzle(r) for r in picked[:ASSESSMENT_COUNT]]
    path = output_dir / "rating_puzzles.json"
    path.write_text(json.dumps(puzzles, ensure_ascii=False))
    return len(puzzles), path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export tier + assessment puzzle JSONs from the Lichess SQLite DB."
    )
    parser.add_argument("input", type=Path, help="Path to lichess_puzzles.sqlite")
    parser.add_argument("output_dir", type=Path, help="Directory to write the JSON files into")
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"Input database not found: {args.input}", file=sys.stderr)
        raise SystemExit(1)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(args.input)
    conn.row_factory = sqlite3.Row
    try:
        total = 0
        for lower in TIER_LOWERS:
            count, path = export_tier(conn, args.output_dir, lower)
            total += count
            print(f"  {path.name}: {count} puzzles ({path.stat().st_size / 1024:.1f} KB)")
        count, path = export_assessment(conn, args.output_dir)
        total += count
        print(f"  {path.name}: {count} puzzles ({path.stat().st_size / 1024:.1f} KB)")
        print(f"Wrote {total} puzzles across {len(list(TIER_LOWERS)) + 1} files into {args.output_dir}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
