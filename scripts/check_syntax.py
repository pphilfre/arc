"""Optional Windows syntax check. This is not an iOS typecheck or build."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".research/python"))
import tree_sitter
import tree_sitter_swift
import yaml

root = Path(__file__).resolve().parents[1]
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors = []
def walk(node, source, path):
    if node.type == "ERROR" or node.is_missing:
        errors.append(path)
        print(path.relative_to(root), node.type, node.start_point, repr(source[node.start_byte:node.end_byte].decode()[:180]))
    for child in node.children:
        walk(child, source, path)
files = [p for directory in ("Arc", "ArcActivity", "Shared", "Tests") for p in (root / directory).rglob("*.swift")]
for path in files:
    source = path.read_bytes()
    walk(parser.parse(source).root_node, source, path)
for path in (root / "project.yml", root / ".github/workflows/build-ios.yml"):
    yaml.safe_load(path.read_text())
print(f"Parsed {len(files)} Swift files and both YAML files; {len(set(errors))} Swift files flagged.")
raise SystemExit(bool(errors))
