#!/usr/bin/env python3
"""
Export N random puzzles from the Lichess SQLite database into a compact JSON
file that the app bundles as its offline puzzle set.

Usage:
    python export_puzzles.py \
        ../data/lichess_puzzles.sqlite \
        ../../DailyTactics/Resources/puzzles.json \
        --count 1000

All Lichess fields are written (id, fen, moves, rating, ratingDeviation,
popularity, playCount, themes, gameUrl, openingTags) so the app has the full
metadata available for future use. Theme tags are filtered down to the app's
`PuzzleTheme` enum identifiers; any Lichess-only tags (crushing, hangingPiece,
long, ...) are dropped.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

# Theme identifiers kept verbatim — these must match the `PuzzleTheme` enum
# raw values in DailyTactics/Sources/PuzzleKit/Puzzle.swift.
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export random puzzles from the Lichess SQLite DB to JSON."
    )
    parser.add_argument("input", type=Path, help="Path to lichess_puzzles.sqlite")
    parser.add_argument("output", type=Path, help="Path to the output JSON file")
    parser.add_argument(
        "--count",
        type=int,
        default=1000,
        help="Number of random puzzles to export (default: 1000)",
    )
    return parser.parse_args()


def export(input_db: Path, output_json: Path, count: int) -> int:
    conn = sqlite3.connect(input_db)
    conn.row_factory = sqlite3.Row
    # ORDER BY RANDOM() over ~6M rows is a one-time cost acceptable for an
    # export. If it ever becomes too slow, sample by random rowid instead.
    rows = conn.execute(
        "SELECT puzzle_id, fen, moves, rating, rating_deviation, popularity, "
        "play_count, themes, game_url, opening_tags "
        "FROM puzzles ORDER BY RANDOM() LIMIT ?",
        (count,),
    ).fetchall()
    conn.close()

    puzzles = []
    for row in rows:
        moves = row["moves"].split()
        if not moves:
            continue
        themes = [t for t in row["themes"].split() if t in KNOWN_THEMES]
        puzzles.append(
            {
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
        )

    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(puzzles, ensure_ascii=False))

    themed = sum(1 for p in puzzles if p["themes"])
    print(f"Wrote {len(puzzles)} puzzles to {output_json}")
    print(f"  with >=1 known theme: {themed}")
    print(f"  size: {output_json.stat().st_size / 1024:.1f} KB")
    return len(puzzles)


def main() -> None:
    args = parse_args()
    if not args.input.is_file():
        print(f"Input database not found: {args.input}", file=sys.stderr)
        raise SystemExit(1)
    if args.count <= 0:
        print("--count must be positive", file=sys.stderr)
        raise SystemExit(1)
    export(args.input, args.output, args.count)


if __name__ == "__main__":
    main()
