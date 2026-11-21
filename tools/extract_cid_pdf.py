#!/usr/bin/env python3
"""CID-font PDF text extractor (stdlib only).

Many vendor manuals embed subset CJK/Latin fonts and store text as 2-byte glyph
codes plus a /ToUnicode CMap. This script merges all ToUnicode CMaps found in
the file and decodes the hex strings in the page content streams.

Good for reading tables out of manuals; not a general PDF renderer.

Usage: python extract_cid_pdf.py in.pdf out.txt
"""
import re
import sys
import zlib

STREAM_RE = re.compile(rb"stream\r?\n(.*?)\r?\nendstream", re.S)


def cmap_from_text(text: str) -> dict[int, str]:
    mapping: dict[int, str] = {}

    for block in re.findall(r"beginbfchar(.*?)endbfchar", text, re.S):
        for src, dst in re.findall(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block):
            code = int(src, 16)
            mapping[code] = units_to_str(dst)

    for block in re.findall(r"beginbfrange(.*?)endbfrange", text, re.S):
        for lo, hi, dst in re.findall(
            r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block
        ):
            start, end, base = int(lo, 16), int(hi, 16), int(dst, 16)
            for offset in range(0, min(end - start, 65535) + 1):
                mapping[start + offset] = chr(base + offset)

    return mapping


def units_to_str(hexstr: str) -> str:
    raw = bytes.fromhex(hexstr)
    # UTF-16BE by convention
    try:
        return raw.decode("utf-16-be")
    except UnicodeDecodeError:
        return "".join(chr(b) for b in raw)


def iter_streams(data: bytes):
    """Yield (index, bytes) for every stream, decompressed when possible."""
    for idx, match in enumerate(STREAM_RE.finditer(data)):
        raw = match.group(1)
        try:
            yield idx, zlib.decompress(raw), True
        except zlib.error:
            yield idx, raw, False


def merge_cmaps(data: bytes) -> dict[int, str]:
    merged: dict[int, str] = {}
    for _, content, _ in iter_streams(data):
        if b"beginbfchar" not in content and b"beginbfrange" not in content:
            continue
        merged.update(cmap_from_text(content.decode("latin-1", "replace")))
    return merged


def decode_content(content: bytes, cmap: dict[int, str]) -> str:
    out: list[str] = []
    i, n = 0, len(content)
    last_y = None
    while i < n:
        c = content[i]
        if c == 0x3C:  # '<' hex string
            j = content.find(b">", i + 1)
            if j == -1:
                break
            hexstr = re.sub(rb"\s", b"", content[i + 1:j])
            if hexstr and all(ch in b"0123456789abcdefABCDEF" for ch in hexstr):
                if len(hexstr) % 2 == 0 and len(hexstr) >= 4:
                    chars = []
                    for k in range(0, len(hexstr), 4):
                        code = int(hexstr[k:k + 4] or b"0", 16)
                        chars.append(cmap.get(code, ""))
                    out.append("".join(chars))
                elif len(hexstr) % 2 == 0:
                    # single byte codes
                    for k in range(0, len(hexstr), 2):
                        out.append(cmap.get(int(hexstr[k:k + 2], 16), ""))
            i = j + 1
            continue
        if content[i:i + 2] == b"Tm":
            tail = content[max(0, i - 80):i]
            nums = re.findall(rb"(-?\d+\.?\d*)", tail)
            if len(nums) >= 6:
                try:
                    y = float(nums[-1])
                    if last_y is not None and abs(y - last_y) > 2:
                        out.append("\n")
                    last_y = y
                except ValueError:
                    pass
            i += 2
            continue
        if content[i:i + 2] == b"ET":
            out.append("\n")
            i += 2
            continue
        i += 1
    text = "".join(out)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    cmap = merge_cmaps(data)
    print(f"cmap entries: {len(cmap)}")
    chunks = []
    for idx, content, compressed in iter_streams(data):
        if not compressed and content.count(b"Tj") + content.count(b"TJ") < 2:
            continue
        if b"Tj" not in content and b"TJ" not in content:
            continue
        text = decode_content(content, cmap).strip()
        if len(text) < 2:
            continue
        chunks.append(f"===== STREAM {idx} =====\n{text}")
    open(dst, "w", encoding="utf-8").write("\n\n".join(chunks))
    print(f"wrote {dst}: {len(chunks)} streams, {sum(len(c) for c in chunks)} chars")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
