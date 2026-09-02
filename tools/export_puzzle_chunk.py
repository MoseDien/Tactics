#!/usr/bin/env python3
"""
Export one chunk of random, never-previously-exported puzzles.

Each run writes a single `puzzle-NNNN.json` (NNNN starting at 0001, one above
the highest existing sequence in the output directory) holding `--count`
random puzzles drawn from the Lichess SQLite database, then records the
exported puzzle ids in an `exported_puzzles` table so no puzzle is ever
exported twice. The JSON shape matches the app's `Puzzle` Codable exactly
(camelCase keys, theme tags filtered to the app's enum) — identical to the
tier files produced by `export_tier_puzzles.py`.

Usage:
    python export_puzzle_chunk.py \\
        ../data/source/lichess_puzzles.sqlite \\
        /path/to/output [--count 1000] [--rating-min 1000] [--rating-max 2000]
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sqlite3
import sys
from pathlib import Path

# Must match the `PuzzleTheme` enum raw values in
# PuzzleKit/Sources/Puzzle.swift.
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

CHUNK_PATTERN = re.compile(r"^puzzle-(\d{4})\.json$")

_CREATE_EXPORTED = """
CREATE TABLE IF NOT EXISTS exported_puzzles (
    puzzle_id   TEXT PRIMARY KEY REFERENCES puzzles(puzzle_id),
    chunk       INTEGER NOT NULL,
    exported_at TEXT NOT NULL
)
"""

_SELECT_UNEXPORTED = (
    "SELECT p.puzzle_id, p.fen, p.moves, p.rating, p.rating_deviation, "
    "p.popularity, p.play_count, p.themes, p.game_url, p.opening_tags "
    "FROM puzzles p "
    "WHERE p.rating >= ? AND p.rating < ? "
    "AND NOT EXISTS (SELECT 1 FROM exported_puzzles e WHERE e.puzzle_id = p.puzzle_id) "
    "ORDER BY RANDOM() LIMIT ?"
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


def next_chunk_sequence(conn: sqlite3.Connection, output_dir: Path) -> int:
    """One above the highest chunk ever recorded in the DB; the directory's
    existing files only matter when they outrank it (e.g. an earlier run wrote
    a file but crashed before marking)."""
    highest = conn.execute("SELECT COALESCE(MAX(chunk), 0) FROM exported_puzzles").fetchone()[0]
    for entry in output_dir.iterdir() if output_dir.is_dir() else []:
        if match := CHUNK_PATTERN.match(entry.name):
            highest = max(highest, int(match.group(1)))
    return highest + 1


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export one chunk of random unexported puzzles as puzzle-NNNN.json."
    )
    parser.add_argument("input", type=Path, help="Path to lichess_puzzles.sqlite")
    parser.add_argument("output_dir", type=Path, help="Directory to write the chunk into")
    parser.add_argument("--count", type=int, default=1000, help="Puzzles per chunk (default 1000)")
    parser.add_argument("--rating-min", type=int, default=1000, help="Inclusive rating lower bound")
    parser.add_argument("--rating-max", type=int, default=2000, help="Exclusive rating upper bound")
    parser.add_argument(
        "--sequence",
        type=int,
        default=None,
        help="Force the chunk sequence (e.g. 0 for the app-bundled chunk) "
        "instead of auto-advancing past the highest recorded chunk",
    )
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"Input database not found: {args.input}", file=sys.stderr)
        raise SystemExit(1)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(args.input)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute(_CREATE_EXPORTED)
        conn.commit()
        sequence = args.sequence if args.sequence is not None else next_chunk_sequence(conn, args.output_dir)
        path = args.output_dir / f"puzzle-{sequence:04d}.json"
        if path.exists():
            print(f"Refusing to overwrite existing {path.name}", file=sys.stderr)
            raise SystemExit(1)

        rows = conn.execute(
            _SELECT_UNEXPORTED, (args.rating_min, args.rating_max, args.count)
        ).fetchall()
        puzzles = [row_to_puzzle(r) for r in rows if r["moves"].split()]
        if not puzzles:
            print(
                f"No unexported puzzles remain in the "
                f"[{args.rating_min}, {args.rating_max}) rating band.",
                file=sys.stderr,
            )
            raise SystemExit(1)

        path.write_text(json.dumps(puzzles, ensure_ascii=False))

        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        conn.executemany(
            "INSERT OR IGNORE INTO exported_puzzles (puzzle_id, chunk, exported_at) "
            "VALUES (?, ?, ?)",
            [(p["id"], sequence, now) for p in puzzles],
        )
        conn.commit()

        ratings = [p["rating"] for p in puzzles]
        remaining = conn.execute(
            "SELECT COUNT(*) FROM puzzles p WHERE p.rating >= ? AND p.rating < ? "
            "AND NOT EXISTS (SELECT 1 FROM exported_puzzles e WHERE e.puzzle_id = p.puzzle_id)",
            (args.rating_min, args.rating_max),
        ).fetchone()[0]
        marked = conn.execute("SELECT COUNT(*) FROM exported_puzzles").fetchone()[0]

        print(f"  {path.name}: {len(puzzles)} puzzles ({path.stat().st_size / 1024:.1f} KB)")
        print(
            f"  rating min/avg/max: {min(ratings)}/{sum(ratings) / len(ratings):.0f}/{max(ratings)}"
        )
        print(f"  total marked exported: {marked}; remaining in band: {remaining}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
