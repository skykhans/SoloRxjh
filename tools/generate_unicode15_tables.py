from pathlib import Path
import unicodedata


EXPECTED_VERSION = "15.0.0"
OUTPUT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "unicode15_data.gd"


def render_dictionary(name: str, entries: dict[int, object]) -> list[str]:
    lines = [f"const {name} := {{"]
    for key, value in sorted(entries.items()):
        if isinstance(value, list):
            rendered_value = "[" + ", ".join(f"0x{item:X}" for item in value) + "]"
        else:
            rendered_value = f"0x{value:X}"
        lines.append(f"\t0x{key:X}: {rendered_value},")
    lines.append("}")
    return lines


def main() -> None:
    if unicodedata.unidata_version != EXPECTED_VERSION:
        raise SystemExit(
            f"Expected Unicode {EXPECTED_VERSION}, found {unicodedata.unidata_version}."
        )

    decomposition: dict[int, list[int]] = {}
    casefold: dict[int, list[int]] = {}
    combining_class: dict[int, int] = {}
    composition: dict[int, int] = {}
    whitespace: list[int] = []

    for codepoint in range(0x110000):
        character = chr(codepoint)
        raw_decomposition = unicodedata.decomposition(character)
        if raw_decomposition and not raw_decomposition.startswith("<"):
            parts = [int(part, 16) for part in raw_decomposition.split()]
            decomposition[codepoint] = parts
            if (
                len(parts) == 2
                and unicodedata.normalize("NFC", "".join(map(chr, parts))) == character
            ):
                composition[(parts[0] << 21) | parts[1]] = codepoint

        folded = character.casefold()
        if folded != character:
            casefold[codepoint] = [ord(item) for item in folded]

        current_class = unicodedata.combining(character)
        if current_class:
            combining_class[codepoint] = current_class

        if character.isspace():
            whitespace.append(codepoint)

    lines = [
        "# Generated from Python's Unicode 15.0.0 database.",
        "# Derived Unicode data are covered by Unicode License V3; see LICENSES/Unicode-15.0.0.txt.",
        "# Regenerate with tools/generate_unicode15_tables.py.",
        "class_name Unicode15Data",
        "extends RefCounted",
        "",
        'const VERSION := "15.0.0"',
        "",
    ]
    lines.extend(render_dictionary("CANONICAL_DECOMPOSITION", decomposition))
    lines.append("")
    lines.extend(render_dictionary("CASE_FOLD", casefold))
    lines.append("")
    lines.extend(render_dictionary("COMBINING_CLASS", combining_class))
    lines.append("")
    lines.extend(render_dictionary("COMPOSITION", composition))
    lines.extend(
        [
            "",
            "const WHITE_SPACE := [",
            "\t" + ", ".join(f"0x{codepoint:X}" for codepoint in whitespace),
            "]",
            "",
        ]
    )
    OUTPUT_PATH.write_text("\n".join(lines), encoding="ascii", newline="\n")
    print(
        "Generated Unicode 15.0.0 tables: "
        f"{len(decomposition)} decompositions, {len(casefold)} case folds, "
        f"{len(combining_class)} combining classes, {len(composition)} compositions."
    )


if __name__ == "__main__":
    main()
