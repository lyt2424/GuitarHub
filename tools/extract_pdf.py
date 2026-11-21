#!/usr/bin/env python3
"""Minimal PDF text extractor (stdlib only).

Good enough for Word/LaTeX generated manuals that use WinAnsi text with
FlateDecode streams. It is NOT a general PDF library: no font subset
remapping, no OCR for scanned pages.

Usage:
    python extract_pdf.py input.pdf output.txt
"""
import re
import sys
import zlib

STREAM_RE = re.compile(rb"stream\r?\n(.*?)\r?\nendstream", re.S)
OBJ_RE = re.compile(rb"(\d+)\s+(\d+)\s+obj(.*?)endobj", re.S)


def decode_pdf_string(raw: bytes) -> str:
    out = []
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch == 0x5C:  # backslash
            i += 1
            if i >= len(raw):
                break
            esc = raw[i]
            mapping = {ord("n"): "\n", ord("r"): "\r", ord("t"): "\t",
                       ord("b"): "\b", ord("f"): "\f",
                       ord("("): "(", ord(")"): ")", ord("\\"): "\\"}
            if esc in mapping:
                out.append(mapping[esc])
                i += 1
            elif 0x30 <= esc <= 0x37:
                digits = ""
                while i < len(raw) and len(digits) < 3 and 0x30 <= raw[i] <= 0x37:
                    digits += chr(raw[i])
                    i += 1
                out.append(chr(int(digits, 8)))
            else:
                i += 1
        else:
            out.append(chr(ch))
            i += 1
    return "".join(out)


def extract_from_content(data: bytes) -> str:
    text_parts = []
    # tokenise ( ... ) strings and <hex> strings with TJ/Tj operators
    i = 0
    last_y = None
    n = len(data)
    while i < n:
        c = data[i]
        if c == 0x28:  # (
            j = i + 1
            depth = 1
            buf = bytearray()
            while j < n:
                b = data[j]
                if b == 0x5C:
                    buf.append(b)
                    if j + 1 < n:
                        buf.append(data[j + 1])
                    j += 2
                    continue
                if b == 0x28:
                    depth += 1
                elif b == 0x29:
                    depth -= 1
                    if depth == 0:
                        break
                buf.append(b)
                j += 1
            text_parts.append(("str", decode_pdf_string(bytes(buf))))
            i = j + 1
            continue
        if c == 0x54 and i + 2 < n and data[i:i + 2] == b"Tm":
            # 1 0 0 1 x y Tm
            tail = data[max(0, i - 80):i]
            nums = re.findall(rb"(-?\d+\.?\d*)", tail)
            if len(nums) >= 6:
                try:
                    y = float(nums[-1])
                    if last_y is not None and abs(y - last_y) > 2:
                        text_parts.append(("nl", "\n"))
                    last_y = y
                except ValueError:
                    pass
            i += 2
            continue
        if c == 0x45 and i + 2 < n and data[i:i + 2] == b"ET":
            text_parts.append(("nl", "\n"))
            i += 2
            continue
        i += 1

    out = []
    for kind, value in text_parts:
        if kind == "nl":
            if out and out[-1] == "\n":
                continue
            out.append(value)
        else:
            out.append(value)
    return "".join(out)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    chunks = []
    for idx, match in enumerate(STREAM_RE.finditer(data)):
        raw = match.group(1)
        try:
            content = zlib.decompress(raw)
        except zlib.error:
            continue
        if b"Tj" not in content and b"TJ" not in content:
            continue
        text = extract_from_content(content)
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
        if len(text) < 2:
            continue
        chunks.append(f"===== STREAM {idx} =====\n{text}")
    open(dst, "w", encoding="utf-8").write("\n\n".join(chunks))
    print(f"wrote {dst}: {len(chunks)} text streams, {sum(len(c) for c in chunks)} chars")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
