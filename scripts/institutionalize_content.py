#!/usr/bin/env python3
"""Remove singular first-person copy while preserving Royalty Buyer's local voice."""

from __future__ import annotations

import json
import pathlib
import re


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content"
FIRST_PERSON = re.compile(r"\b(i|me|my|myself)\b", re.I)


def owner_question(text: str) -> str:
    replacements = (
        (r"\bI['’]m\b", "you are"),
        (r"\bI['’]ve\b", "you have"),
        (r"\bI['’]d\b", "you would"),
        (r"\bI['’]ll\b", "you will"),
        (r"\bI don['’]t\b", "you do not"),
        (r"\bI can['’]t\b", "you cannot"),
        (r"\bmyself\b", "yourself"),
        (r"\bmy\b", "your"),
        (r"\bme\b", "you"),
        (r"\bI\b", "you"),
    )
    for pattern, replacement in replacements:
        text = re.sub(pattern, replacement, text, flags=re.I)
    text = re.sub(r"^You only own\b", "If you only own", text)
    text = re.sub(r"^You have\b", "If you have", text)
    return text[0].upper() + text[1:] if text else text


def business_narrative(text: str) -> str:
    text = re.sub(
        r"My grandfather used to say the Anadarko Basin was the basin that never quit surprising people\.",
        "An old ranch-country saying calls the Anadarko Basin the basin that never quit surprising people.",
        text,
        flags=re.I,
    )
    text = re.sub(
        r"Our own family's minerals went this route before we ever sold a single acre to anyone else\. "
        r"My great-grandfather owned a full quarter section outright\. By the time it reached my father's "
        r"generation it had been divided among six heirs and their children, and my own royalty statement "
        r"showed an interest so small the decimal point had four zeros in front of it\.",
        "The family experience behind Royalty Buyer followed this same path before the desk reviewed another "
        "owner's sale. A great-grandfather held a full quarter section. By the next generations, that interest "
        "had passed among six heirs and their children, and the royalty statement carried a decimal with four "
        "zeros in front of it.",
        text,
        flags=re.I,
    )
    replacements = (
        (r"\bI['’]m\b", "the royalty desk is"),
        (r"\bI['’]ve\b", "the royalty desk has"),
        (r"\bI['’]d\b", "the royalty desk would"),
        (r"\bI['’]ll\b", "the royalty desk will"),
        (r"\bmyself\b", "the royalty desk"),
        (r"\bmy\b", "the owner's"),
        (r"\bme\b", "the royalty desk"),
        (r"\bI\b", "the royalty desk"),
    )
    for pattern, replacement in replacements:
        text = re.sub(pattern, replacement, text, flags=re.I)
    grammar = (
        (r"\bthe royalty desk am\b", "the royalty desk is"),
        (r"\bthe royalty desk have\b", "the royalty desk has"),
        (r"\bthe royalty desk do\b", "the royalty desk does"),
        (r"\bthe royalty desk don['’]t\b", "the royalty desk does not"),
        (r"\bthe royalty desk ask\b", "the royalty desk asks"),
        (r"\bthe royalty desk need\b", "the royalty desk needs"),
        (r"\bthe royalty desk work\b", "the royalty desk works"),
    )
    for pattern, replacement in grammar:
        text = re.sub(pattern, replacement, text, flags=re.I)
    return text


def rewrite(value, key: str = ""):
    if isinstance(value, dict):
        return {child_key: rewrite(child, child_key) for child_key, child in value.items()}
    if isinstance(value, list):
        return [rewrite(child, key) for child in value]
    if isinstance(value, str):
        return owner_question(value) if key == "question" else business_narrative(value)
    return value


def main() -> None:
    changed = 0
    failures: list[str] = []
    for path in sorted(CONTENT.rglob("*.json")):
        before = path.read_text()
        revised = rewrite(json.loads(before))
        after = json.dumps(revised, indent=2, ensure_ascii=False) + "\n"
        if after != before:
            path.write_text(after)
            changed += 1
        for match in FIRST_PERSON.finditer(after):
            failures.append(f"{path.relative_to(ROOT)}: {match.group(0)}")
    if failures:
        raise SystemExit("Singular first-person copy remains:\n" + "\n".join(failures[:40]))
    print(f"INSTITUTIONAL VOICE: PASS — {changed} content files updated; zero I/me/my/myself")


if __name__ == "__main__":
    main()
