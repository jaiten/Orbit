"""Source-level checks usable on Windows; not a replacement for xcodebuild test.

Install: python -m pip install tree-sitter tree-sitter-swift pyyaml
Run: python scripts/validate_sources.py
"""
from pathlib import Path
import json
import sys
import tree_sitter
import tree_sitter_swift
import yaml

root = Path(__file__).resolve().parents[1]
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
failures = []
files = sorted((root / "ios").rglob("*.swift"))
for path in files:
    tree = parser.parse(path.read_bytes())
    def visit(node):
        if node.type == "ERROR" or node.is_missing:
            failures.append(f"{path.relative_to(root)}:{node.start_point.row + 1}: {node.type}")
        for child in node.children:
            visit(child)
    visit(tree.root_node)

spec = yaml.safe_load((root / "ios/project.yml").read_text())
for name, target in spec["targets"].items():
    for source in target["sources"]:
        if not (root / "ios" / source).is_dir():
            failures.append(f"{name}: missing source directory {source}")
    for dependency in target.get("dependencies", []):
        if dependency["target"] not in spec["targets"]:
            failures.append(f"{name}: missing target dependency")
for path in root.rglob("*.json"):
    if not any(part in {"node_modules", "dist", ".git"} for part in path.parts):
        json.loads(path.read_text(encoding="utf-8"))
if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"PASS: {len(files)} Swift files parsed; project source paths, target dependencies, and JSON valid.")
print("Swift type checking, SwiftData macros, simulator behavior, and XCTest still require Xcode.")
