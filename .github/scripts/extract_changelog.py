import os
import re
import subprocess
import sys

def main():
    ver = sys.argv[1] if len(sys.argv) > 1 else ""
    tag = sys.argv[2] if len(sys.argv) > 2 else f"v{ver}"
    
    notes = ""
    if os.path.exists("CHANGELOG.md") and ver:
        try:
            with open("CHANGELOG.md", "r", encoding="utf-8") as f:
                content = f.read()
            pattern = rf"## \[{re.escape(ver)}\][^\n]*\n([\s\S]*?)(?=\n## \[|\Z)"
            m = re.search(pattern, content)
            if m:
                notes = m.group(1).strip().rstrip("---").strip()
        except Exception:
            pass

    if not notes:
        try:
            notes = subprocess.check_output(["git", "log", "-1", "--pretty=%B"], text=True).strip()
        except Exception:
            notes = f"✨ Release {tag}"

    with open("release_notes.md", "w", encoding="utf-8") as out:
        out.write(notes if notes else f"✨ Release {tag}")
    print(f"Extracted {len(notes)} chars of release notes for {ver} ({tag})")

if __name__ == "__main__":
    main()
