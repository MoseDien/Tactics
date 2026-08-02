#!/usr/bin/env python3
"""
Import the Lichess puzzle database (.csv.zst) into SQLite.

Usage:
    python import_lichess_puzzles.py \
        lichess_db_puzzle.csv.zst \
        lichess_puzzles.sqlite

Dependency:
    pip install zstandard
"""

from __future__ import annotations

import argparse
import csv
import io
import sqlite3
import sys
import time
from pathlib import Path
from typing import Iterable, Iterator

try:
    import zstandard as zstd
except ImportError:
    print(
        "Missing dependency: zstandard\n"
        "Install it with:\n"
        "  pip install zstandard",
        file=sys.stderr,
    )
    raise SystemExit(1)


CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS puzzles (
    puzzle_id          TEXT PRIMARY KEY,
    fen                TEXT NOT NULL,
    moves              TEXT NOT NULL,
    rating             INTEGER NOT NULL,
    rating_deviation   INTEGER NOT NULL,
    popularity         INTEGER NOT NULL,
    play_count         INTEGER NOT NULL,
    themes             TEXT NOT NULL,
    game_url           TEXT NOT NULL,
    opening_tags       TEXT NOT NULL
);
"""

INSERT_SQL = """
INSERT OR REPLACE INTO puzzles (
    puzzle_id,
    fen,
    moves,
    rating,
    rating_deviation,
    popularity,
    play_count,
    themes,
    game_url,
    opening_tags
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
"""

INDEX_SQL = [
    "CREATE INDEX IF NOT EXISTS idx_puzzles_rating ON puzzles(rating);",
    "CREATE INDEX IF NOT EXISTS idx_puzzles_popularity ON puzzles(popularity);",
    "CREATE INDEX IF NOT EXISTS idx_puzzles_play_count ON puzzles(play_count);",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stream-import the Lichess puzzle .csv.zst file into SQLite."
    )
    parser.add_argument("input", type=Path, help="Path to lichess_db_puzzle.csv.zst")
    parser.add_argument("output", type=Path, help="Path to output SQLite database")
    parser.add_argument(
        "--batch-size",
        type=int,
        default=10_000,
        help="Rows committed per batch (default: 10000)",
    )
    parser.add_argument(
        "--progress-every",
        type=int,
        default=100_000,
        help="Print progress every N rows (default: 100000)",
    )
    parser.add_argument(
        "--no-indexes",
        action="store_true",
        help="Skip creating indexes after import",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Delete the output database first if it already exists",
    )
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if not args.input.is_file():
        raise FileNotFoundError(f"Input file not found: {args.input}")

    if args.batch_size <= 0:
        raise ValueError("--batch-size must be greater than 0")

    if args.progress_every <= 0:
        raise ValueError("--progress-every must be greater than 0")

    if args.output.exists() and args.replace:
        args.output.unlink()

    args.output.parent.mkdir(parents=True, exist_ok=True)


def configure_database(conn: sqlite3.Connection) -> None:
    # Fast import settings. The database remains durable after close.
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    conn.execute("PRAGMA temp_store = MEMORY;")
    conn.execute("PRAGMA cache_size = -200000;")  # About 200 MB
    conn.execute(CREATE_TABLE_SQL)


def normalize_row(row: list[str], line_number: int) -> tuple:
    if len(row) != 10:
        raise ValueError(
            f"Invalid CSV row at line {line_number}: "
            f"expected 10 columns, got {len(row)}"
        )

    return (
        row[0],         # PuzzleId
        row[1],         # FEN
        row[2],         # Moves
        int(row[3]),    # Rating
        int(row[4]),    # RatingDeviation
        int(row[5]),    # Popularity
        int(row[6]),    # NbPlays
        row[7],         # Themes
        row[8],         # GameUrl
        row[9],         # OpeningTags
    )


def iter_puzzle_rows(input_path: Path) -> Iterator[tuple]:
    decompressor = zstd.ZstdDecompressor()

    with input_path.open("rb") as compressed:
        with decompressor.stream_reader(compressed) as reader:
            text_stream = io.TextIOWrapper(
                reader,
                encoding="utf-8",
                newline="",
            )
            csv_reader = csv.reader(text_stream)

            header = next(csv_reader, None)
            expected_header = [
                "PuzzleId",
                "FEN",
                "Moves",
                "Rating",
                "RatingDeviation",
                "Popularity",
                "NbPlays",
                "Themes",
                "GameUrl",
                "OpeningTags",
            ]

            if header != expected_header:
                raise ValueError(
                    "Unexpected CSV header.\n"
                    f"Expected: {expected_header}\n"
                    f"Received: {header}"
                )

            for line_number, row in enumerate(csv_reader, start=2):
                yield normalize_row(row, line_number)


def batched(rows: Iterable[tuple], batch_size: int) -> Iterator[list[tuple]]:
    batch: list[tuple] = []

    for row in rows:
        batch.append(row)
        if len(batch) >= batch_size:
            yield batch
            batch = []

    if batch:
        yield batch


def create_indexes(conn: sqlite3.Connection) -> None:
    print("Creating indexes...")
    for statement in INDEX_SQL:
        conn.execute(statement)
    conn.commit()


def import_database(args: argparse.Namespace) -> int:
    started_at = time.monotonic()
    imported = 0

    conn = sqlite3.connect(args.output)

    try:
        configure_database(conn)

        for batch in batched(iter_puzzle_rows(args.input), args.batch_size):
            with conn:
                conn.executemany(INSERT_SQL, batch)

            imported += len(batch)

            if (
                imported % args.progress_every < args.batch_size
                or len(batch) < args.batch_size
            ):
                elapsed = time.monotonic() - started_at
                rate = imported / elapsed if elapsed > 0 else 0
                print(
                    f"Imported {imported:,} rows "
                    f"({rate:,.0f} rows/sec)"
                )

        if not args.no_indexes:
            create_indexes(conn)

        conn.execute("PRAGMA optimize;")
        conn.commit()

    finally:
        conn.close()

    elapsed = time.monotonic() - started_at
    size_mb = args.output.stat().st_size / (1024 * 1024)

    print()
    print("Import complete.")
    print(f"Rows:     {imported:,}")
    print(f"Database: {args.output}")
    print(f"Size:     {size_mb:,.1f} MB")
    print(f"Time:     {elapsed:,.1f} seconds")

    return imported


def main() -> None:
    args = parse_args()

    try:
        validate_args(args)
        import_database(args)
    except KeyboardInterrupt:
        print("\nImport interrupted.", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
