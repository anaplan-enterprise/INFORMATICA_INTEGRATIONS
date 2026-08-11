#!/usr/bin/env python3
"""Apply folder-scoped Dev→Prod keyword replacements under Explore/.

Resolves the keyword map from the first path segment under Explore/:
  Explore/IT_EAI/WD_Coupa/...  →  config/keyword-maps/IT_EAI.yml

Usage:
  python scripts/replace_keywords.py --path Explore/IT_EAI
  python scripts/replace_keywords.py --path Explore/IT_EAI/WD_Coupa --dry-run
  python scripts/replace_keywords.py --path Explore/IT_EAI --report /tmp/report.json
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None  # type: ignore


REPO_ROOT = Path(__file__).resolve().parents[1]
MAPS_DIR = REPO_ROOT / "config" / "keyword-maps"
TEXT_EXTENSIONS = {
    ".xml",
    ".json",
    ".yml",
    ".yaml",
    ".properties",
    ".txt",
    ".csv",
    ".sql",
    ".sh",
    ".bat",
    ".cmd",
    ".ps1",
    ".js",
    ".ts",
    ".py",
    ".md",
    ".conf",
    ".cfg",
    ".ini",
    ".html",
    ".htm",
    ".css",
}


def load_map(folder_name: str) -> dict[str, Any]:
    map_path = MAPS_DIR / f"{folder_name}.yml"
    if not map_path.is_file():
        raise FileNotFoundError(
            f"No keyword map for Explore/{folder_name}/. "
            f"Expected file: {map_path.relative_to(REPO_ROOT)}"
        )
    if yaml is None:
        raise RuntimeError("PyYAML is required. Install with: pip install pyyaml")
    with map_path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data.get("replacements"), list) or not data["replacements"]:
        raise ValueError(f"{map_path.name}: 'replacements' must be a non-empty list")
    return data


def resolve_top_folder(
    relative_path: str, must_exist: bool = True
) -> tuple[str, Path]:
    """Return (top_folder_name, absolute target path) for an Explore/... path."""
    rel = Path(relative_path)
    parts = rel.parts
    if not parts or parts[0] != "Explore":
        raise ValueError(
            f"Path must start with Explore/: got '{relative_path}'"
        )
    if len(parts) < 2:
        raise ValueError("Provide at least Explore/<FOLDER>, e.g. Explore/IT_EAI")
    top = parts[1]
    target = REPO_ROOT / rel
    if must_exist and not target.exists():
        raise FileNotFoundError(f"Target path does not exist: {rel}")
    return top, target


def is_excluded(path: Path, exclude_globs: list[str]) -> bool:
    rel = path.relative_to(REPO_ROOT).as_posix()
    return any(fnmatch.fnmatch(rel, pattern) for pattern in exclude_globs)


def should_process(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.suffix.lower() in TEXT_EXTENSIONS:
        return True
    # IICS objects are often extensionless or .XML; try decode for unknowns
    return path.suffix == "" or path.suffix.lower() in {".xml", ".JSON"}


def apply_replacements(
    content: str, replacements: list[dict[str, str]]
) -> tuple[str, list[dict[str, Any]]]:
    hits: list[dict[str, Any]] = []
    updated = content
    for rule in replacements:
        find = rule.get("find")
        replace = rule.get("replace")
        if find is None or replace is None:
            continue
        count = updated.count(find)
        if count:
            updated = updated.replace(find, replace)
            hits.append({"find": find, "replace": replace, "count": count})
    return updated, hits


def iter_files(target: Path):
    if target.is_file():
        yield target
        return
    yield from sorted(p for p in target.rglob("*") if p.is_file())


def process_file(
    file_path: Path,
    replacements: list[dict[str, str]],
    exclude_globs: list[str],
    dry_run: bool,
    report: dict[str, Any],
) -> None:
    report["files_scanned"] += 1
    if is_excluded(file_path, exclude_globs):
        return
    if not should_process(file_path):
        try:
            raw = file_path.read_bytes()
            if b"\x00" in raw[:2048]:
                return
            text = raw.decode("utf-8")
        except (UnicodeDecodeError, OSError):
            return
    else:
        try:
            text = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            try:
                text = file_path.read_text(encoding="latin-1")
            except OSError:
                return

    new_text, hits = apply_replacements(text, replacements)
    if not hits:
        return

    rel = file_path.relative_to(REPO_ROOT).as_posix()
    report["files_changed"] += 1
    report["changes"].append({"file": rel, "hits": hits})
    if not dry_run:
        file_path.write_text(new_text, encoding="utf-8")


def run(
    path: str,
    dry_run: bool = False,
    files_from: str | None = None,
) -> dict[str, Any]:
    top, target = resolve_top_folder(path, must_exist=not bool(files_from))
    kw_map = load_map(top)
    replacements = kw_map["replacements"]
    exclude_globs = list(kw_map.get("exclude_globs") or [])

    report: dict[str, Any] = {
        "scope_folder": top,
        "target": path,
        "map_file": f"config/keyword-maps/{top}.yml",
        "dry_run": dry_run,
        "files_scanned": 0,
        "files_changed": 0,
        "changes": [],
    }

    if files_from:
        list_path = Path(files_from)
        if not list_path.is_file():
            raise FileNotFoundError(f"files list not found: {files_from}")
        for line in list_path.read_text(encoding="utf-8").splitlines():
            rel = line.strip()
            if not rel or rel.startswith("#"):
                continue
            file_path = REPO_ROOT / rel
            if not file_path.is_file():
                continue
            process_file(file_path, replacements, exclude_globs, dry_run, report)
        return report

    for file_path in iter_files(target):
        process_file(file_path, replacements, exclude_globs, dry_run, report)

    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--path",
        required=True,
        help="Repo-relative path under Explore/, e.g. Explore/IT_EAI or Explore/IT_EAI/WD_Coupa",
    )
    parser.add_argument(
        "--files-from",
        help="Optional file listing repo-relative paths to process (change set)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report replacements without writing files",
    )
    parser.add_argument(
        "--report",
        help="Optional path to write JSON report",
    )
    args = parser.parse_args()

    try:
        report = run(args.path, dry_run=args.dry_run, files_from=args.files_from)
    except (FileNotFoundError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    summary = (
        f"scope={report['scope_folder']} scanned={report['files_scanned']} "
        f"changed={report['files_changed']} dry_run={report['dry_run']}"
    )
    print(summary)
    for change in report["changes"]:
        hit_str = ", ".join(
            f"{h['find']!r}→{h['replace']!r}×{h['count']}" for h in change["hits"]
        )
        print(f"  {change['file']}: {hit_str}")

    if args.report:
        out = Path(args.report)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"Wrote report: {out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
