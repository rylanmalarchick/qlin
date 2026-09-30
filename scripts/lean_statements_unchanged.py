"""Check that every declaration statement in a draft Lean file is unchanged.

Usage: python scripts/lean_statements_unchanged.py GIT_REV FILE...

For each FILE, the version at GIT_REV is the draft. Every theorem or
lemma statement in the draft (from the keyword up to and including
`:=`) and every other declaration (def, structure, inductive, abbrev,
instance) in full must appear byte for byte in the current file. New
declarations (helper lemmas) are allowed. Exit 1 on any change.
"""

import re
import subprocess
import sys

KEYWORDS = r"(?:private |protected |noncomputable )*(theorem|lemma|def|structure|inductive|abbrev|instance)\b"


def chunks(text: str) -> list[str]:
    """Declarations of `text`, each cut at the next declaration start,
    a `namespace`, `end`, `mutual`, or `variable` line."""
    starts = [m.start() for m in re.finditer(r"^" + KEYWORDS, text, re.M)]
    stops = sorted(set(starts) | {m.start() for m in re.finditer(
        r"^(namespace|end|mutual|variable|section|open)\b", text, re.M)} | {len(text)})
    out = []
    for s in starts:
        e = min(x for x in stops if x > s)
        body = text[s:e].rstrip()
        # A docstring at the end belongs to the next declaration.
        body = re.sub(r"\n/--(?:(?!-/).)*-/\Z", "", body, flags=re.S).rstrip()
        kind = re.match(KEYWORDS, body).group(1)
        if kind in ("theorem", "lemma"):
            i = body.find(":= by")
            body = body[: i + len(":=")] if i >= 0 else body
        out.append(body)
    return out


def main() -> int:
    rev, files = sys.argv[1], sys.argv[2:]
    bad = 0
    for f in files:
        draft = subprocess.run(["git", "show", f"{rev}:{f}"], capture_output=True,
                               text=True, check=True).stdout
        now = open(f).read()
        for c in chunks(draft):
            if c not in now:
                bad += 1
                print(f"{f}: changed or missing:\n{c}\n")
    print(f"{len(files)} files, {bad} changed statements")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
