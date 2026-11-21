#!/usr/bin/env python3
"""Spark 7bit 打包/解包算法自检（纯标准库，可直接运行）。

对应 iOS 端 GuitarHub/Codecs/SparkProtocol.swift 的 frame()/unpack()。
用于在没有真机的情况下先确认字节级算法自洽。

    python tools/spark_frame_test.py
"""
import random


def frame(cmd: int, sub: int, payload: bytes, sequence: int) -> bytes:
    packed = bytearray()
    index = 0
    while index < len(payload):
        end = min(index + 7, len(payload))
        mask = 0
        for offset in range(end - index):
            if payload[index + offset] & 0x80:
                mask |= 1 << offset
        packed.append(mask)
        for offset in range(index, end):
            packed.append(payload[offset] & 0x7F)
        index = end
    checksum = 0
    for b in packed:
        checksum ^= b
    return bytes([0xF0, 0x01, sequence, checksum, cmd, sub]) + bytes(packed) + bytes([0xF7])


def unpack(packed: bytes, cmd: int, sub: int):
    data = bytearray()
    total, part_index = 1, 0
    bits, bitmask = 0, 1
    counter = 0
    is_preset = sub == 0x01 and cmd in (0x01, 0x03)
    for byte in packed:
        if counter % 8 == 0:
            bits, bitmask = byte, 1
        else:
            value = byte
            if bits & bitmask:
                value |= 0x80
            bitmask <<= 1
            if is_preset and 1 <= counter <= 3:
                if counter == 1:
                    total = value
                if counter == 2:
                    part_index = value
            else:
                data.append(value)
        counter += 1
        if cmd == 0x03 and sub == 0x01 and counter == 32:
            counter = 0
        if cmd == 0x01 and sub == 0x01 and counter == 150:
            counter = 0
    return total, part_index, bytes(data)


def decode_frame(frame_bytes: bytes):
    """返回 (cmd, sub, seq, payload)。对应 Decoder.parseFrame。"""
    assert frame_bytes[0] == 0xF0 and frame_bytes[1] == 0x01
    seq, checksum, cmd, sub = frame_bytes[2], frame_bytes[3], frame_bytes[4], frame_bytes[5]
    packed = frame_bytes[6:-1]
    calculated = 0
    for b in packed:
        calculated ^= b
    total, part_index, data = unpack(packed, cmd, sub)
    return cmd, sub, seq, calculated == checksum, total, part_index, data


def test_roundtrip():
    cases = [
        (0x02, 0x11, b""),
        (0x01, 0x15, bytes([12, 0xAC]) + b"bias.reverb" + bytes([0xC3])),
        (0x01, 0x04, bytes([5, 0xA5]) + b"Twin" + bytes([0x00, 0xCA, 0x3F, 0x00, 0x00, 0x00])),
        (0x01, 0x38, bytes([0x00, 0x02])),
        (0x02, 0x01, bytes([0x01, 0x00]) + bytes(30)),
    ]
    for cmd, sub, payload in cases:
        wire = frame(cmd, sub, payload, 7)
        dcmd, dsub, dseq, checksum_ok, total, index, data = decode_frame(wire)
        assert (dcmd, dsub, dseq) == (cmd, sub, 7), (dcmd, dsub, dseq)
        assert checksum_ok, "checksum mismatch"
        assert data == payload, (data.hex(), payload.hex())
        print(f"OK  {cmd:02X}{sub:02X}  payload={len(payload):2d}B  packed={len(wire)-7:2d}B")


def test_high_bits():
    # 覆盖所有 0x80 位置：保证掩码逐位正确
    for position in range(21):
        payload = bytearray(21)
        payload[position] = 0x80 | (position + 1)
        wire = frame(0x01, 0x04, bytes(payload), 1)
        _, _, _, ok, _, _, data = decode_frame(wire)
        assert ok and data == bytes(payload), position
    print("OK  高位掩码（21 个位置全覆盖）")


def test_preset_chunk_header():
    # 预设分块：两个数据字节 + 3 字节块头 + 数据。块头位于 counter 1..3。
    data = b"hello-preset"
    chunk = bytes([2, 0, len(data)]) + data   # total=2, index=0, len
    payload = chunk
    wire = frame(0x01, 0x01, payload, 9)
    _, _, _, ok, total, index, out = decode_frame(wire)
    assert ok and total == 2 and index == 0, (total, index)
    assert out == data, out
    print("OK  预设分块头剥离")


def test_noise():
    random.seed(1)
    for _ in range(200):
        length = random.randint(0, 60)
        payload = bytes(random.getrandbits(8) for _ in range(length))
        cmd, sub = 0x01, 0x04
        wire = frame(cmd, sub, payload, random.randint(0, 255))
        _, _, _, ok, _, _, data = decode_frame(wire)
        assert ok and data == payload
    print("OK  200 组随机负载")


if __name__ == "__main__":
    test_roundtrip()
    test_high_bits()
    test_preset_chunk_header()
    test_noise()
    print("all passed")
