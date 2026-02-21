#!/usr/bin/env python3
"""Generate Sphinx RST API documentation from ``nim jsondoc`` JSON output.

Usage::

    python docs/generate_rst.py            # uses 'nim' from PATH
    NIM=/path/to/nim python docs/generate_rst.py

Outputs RST files into ``docs/api/`` and a JSON cache into ``docs/_nim_json/``.
The RST files are then built into HTML by Sphinx.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).parent.parent
SRC_DIR = REPO_ROOT / "src"
DOCS_DIR = Path(__file__).parent
API_DIR = DOCS_DIR / "api"
NIM_JSON_DIR = DOCS_DIR / "_nim_json"

# ---------------------------------------------------------------------------
# Module list  (module_name, source_path, human_title)
# ---------------------------------------------------------------------------
MODULES: list[tuple[str, Path, str]] = [
    ("nimpulseqgui",   SRC_DIR / "nimpulseqgui.nim",                   "nimpulseqgui — Top-level API"),
    ("definitions",    SRC_DIR / "nimpulseqgui" / "definitions.nim",   "definitions — Core types"),
    ("sequenceexe",    SRC_DIR / "nimpulseqgui" / "sequenceexe.nim",   "sequenceexe — CLI entry point"),
    ("sequencegui",    SRC_DIR / "nimpulseqgui" / "sequencegui.nim",   "sequencegui — Main GUI window"),
    ("propertyedit",   SRC_DIR / "nimpulseqgui" / "propertyedit.nim",  "propertyedit — Property editors"),
    ("io",             SRC_DIR / "nimpulseqgui" / "io.nim",            "io — Protocol persistence"),
]

# Symbol kind → section heading (and display order)
_KIND_ORDER = [
    "skType",
    "skConst",
    "skProc",
    "skFunc",
    "skMethod",
    "skIterator",
    "skTemplate",
    "skMacro",
    "skLet",
    "skVar",
]
_KIND_LABELS: dict[str, str] = {
    "skType":     "Types",
    "skConst":    "Constants",
    "skProc":     "Procedures",
    "skFunc":     "Functions",
    "skMethod":   "Methods",
    "skIterator": "Iterators",
    "skTemplate": "Templates",
    "skMacro":    "Macros",
    "skLet":      "Lets",
    "skVar":      "Variables",
}


# ---------------------------------------------------------------------------
# HTML → RST helpers
# ---------------------------------------------------------------------------

def _html_to_rst(html: str) -> str:
    """Convert nim jsondoc HTML description fragment to plain RST."""
    if not html:
        return ""

    # <tt class="docutils literal"><span class="pre"><span class="...">TEXT</span></span></tt>
    # → ``TEXT``
    def _replace_tt(m: re.Match) -> str:
        inner = re.sub(r"<[^>]+>", "", m.group(1))
        return f"``{inner}``"

    text = re.sub(r"<tt[^>]*>(.*?)</tt>", _replace_tt, html, flags=re.DOTALL)

    # <p>...</p> → paragraph with blank lines
    text = re.sub(r"<p>(.*?)</p>", r"\1\n\n", text, flags=re.DOTALL)

    # <b>/<strong> → **bold**
    text = re.sub(r"<(?:b|strong)>(.*?)</(?:b|strong)>", r"**\1**", text)

    # <em>/<i> → *italic*
    text = re.sub(r"<(?:em|i)>(.*?)</(?:em|i)>", r"*\1*", text)

    # <ul>/<li> → RST bullet list
    text = re.sub(r"<ul[^>]*>", "\n", text)
    text = re.sub(r"</ul>", "\n", text)
    text = re.sub(r"<li>(.*?)</li>", r"\n- \1", text, flags=re.DOTALL)

    # Strip any remaining tags
    text = re.sub(r"<[^>]+>", "", text)

    # Decode common HTML entities
    text = (
        text.replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&")
            .replace("&quot;", '"')
            .replace("&#39;", "'")
            .replace("&nbsp;", " ")
    )

    # Normalise whitespace: collapse multiple blank lines
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


_PRAGMA_RE = re.compile(r"\s*\{\..*?\.\}", re.DOTALL)


def _clean_code(code: str) -> str:
    """Strip Nim compiler pragmas from a proc signature."""
    return _PRAGMA_RE.sub("", code).strip()


# ---------------------------------------------------------------------------
# nim jsondoc runner
# ---------------------------------------------------------------------------

def _run_jsondoc(nim_file: Path, out_file: Path) -> bool:
    """Invoke ``nim jsondoc`` and write JSON to *out_file*. Returns True on success."""
    out_file.parent.mkdir(parents=True, exist_ok=True)
    nim_exe = os.environ.get("NIM", "nim")
    try:
        result = subprocess.run(
            [nim_exe, "jsondoc", "--hints:off", f"--out:{out_file}", str(nim_file)],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(
                f"  Warning: nim jsondoc failed for {nim_file.name}:\n"
                f"    {result.stderr.strip()[:300]}",
                file=sys.stderr,
            )
            return False
        if not out_file.exists():
            print(f"  Warning: {out_file} was not created.", file=sys.stderr)
            return False
        return True
    except FileNotFoundError:
        print(
            "  Error: 'nim' executable not found.\n"
            "  Set the NIM environment variable or ensure nim is in PATH.",
            file=sys.stderr,
        )
        return False


# ---------------------------------------------------------------------------
# RST generation
# ---------------------------------------------------------------------------

def _make_module_rst(module_name: str, title: str, data: dict) -> str:
    """Return the full RST string for one module."""
    lines: list[str] = []

    # Page title (double overline/underline)
    bar = "=" * len(title)
    lines += [bar, title, bar, ""]

    module_desc = _html_to_rst(data.get("moduleDescription", ""))
    if module_desc:
        lines += [module_desc, ""]

    # Group entries by kind, preserving source order within each group
    by_kind: dict[str, list[dict]] = {}
    for entry in data.get("entries", []):
        kind = entry.get("type", "skProc")
        by_kind.setdefault(kind, []).append(entry)

    for kind in _KIND_ORDER:
        entries = by_kind.get(kind)
        if not entries:
            continue

        section = _KIND_LABELS.get(kind, kind)
        lines += [section, "-" * len(section), ""]

        # Track seen names to disambiguate overloaded symbols
        name_count: dict[str, int] = {}

        for entry in entries:
            name = entry["name"]
            code = _clean_code(entry.get("code", ""))
            desc = _html_to_rst(entry.get("description", ""))

            # Unique Sphinx cross-reference label for overloaded procs
            count = name_count.get(name, 0)
            name_count[name] = count + 1
            label = f"{module_name}.{name}" if count == 0 else f"{module_name}.{name}.{count}"
            lines += [f".. _{label}:", ""]

            # Symbol heading; append overload index when name repeats
            heading = name if count == 0 else f"{name} ({count + 1})"
            lines += [heading, "~" * len(heading), ""]

            if code:
                lines += [".. code-block:: nim", ""]
                for code_line in code.splitlines():
                    lines.append("   " + code_line)
                lines.append("")

            if desc:
                lines += [desc, ""]

    return "\n".join(lines) + "\n"


def _make_api_index(generated: list[str]) -> str:
    """Return RST for docs/api/index.rst."""
    bar = "=" * 13
    lines = [
        bar,
        "API Reference",
        bar,
        "",
        "Complete reference for all exported symbols.",
        "Generated automatically from source docstrings via ``nim jsondoc``.",
        "",
        ".. toctree::",
        "   :maxdepth: 1",
        "   :caption: Modules",
        "",
    ]
    for name in generated:
        lines.append(f"   {name}")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    API_DIR.mkdir(parents=True, exist_ok=True)
    NIM_JSON_DIR.mkdir(parents=True, exist_ok=True)

    generated: list[str] = []
    errors: list[str] = []

    for module_name, nim_file, title in MODULES:
        print(f"  [{module_name}]", end=" ", flush=True)
        json_file = NIM_JSON_DIR / f"{module_name}.json"

        if not _run_jsondoc(nim_file, json_file):
            errors.append(module_name)
            print("FAILED")
            continue

        try:
            data = json.loads(json_file.read_text())
        except (json.JSONDecodeError, OSError) as exc:
            print(f"FAILED (JSON parse: {exc})")
            errors.append(module_name)
            continue

        rst_content = _make_module_rst(module_name, title, data)
        rst_file = API_DIR / f"{module_name}.rst"
        rst_file.write_text(rst_content, encoding="utf-8")
        generated.append(module_name)
        print(f"-> docs/api/{module_name}.rst")

    # Write api/index.rst
    index_rst = API_DIR / "index.rst"
    index_rst.write_text(_make_api_index(generated), encoding="utf-8")
    print(f"\nWrote docs/api/index.rst  ({len(generated)} modules)")

    if errors:
        print(f"\nFailed modules: {', '.join(errors)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
