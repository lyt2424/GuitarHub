#!/usr/bin/env python3
"""BLE 探测/抓包工具（用于给新设备写 profile 或逆向私有协议）。

依赖 bleak：  pip install bleak

用法：
    python tools/ble_probe.py scan
    python tools/ble_probe.py dump  --name "Spark MINI" [--seconds 10]
    python tools/ble_probe.py watch --name "Pulze" --seconds 30
    python tools/ble_probe.py write --name "MyPedal" --char FFC1 --hex "01FE0000"

说明：
- Windows / macOS 均可运行，但 Windows 需要系统已配对或允许扫描到设备。
- 只能同时连接一台设备；测完记得断开（Ctrl+C）。
"""
import argparse
import asyncio
import sys
import time

try:
    from bleak import BleakClient, BleakScanner
except ImportError:  # pragma: no cover
    print("缺少 bleak：pip install bleak", file=sys.stderr)
    raise SystemExit(1)


def hexdump(data: bytes) -> str:
    return " ".join(f"{b:02X}" for b in data)


async def cmd_scan(args):
    print("扫描 8 秒…")
    devices = await BleakScanner.discover(timeout=8)
    for d in devices:
        print(f"{d.address:<20} {d.name or '(未命名)':<28} rssi={getattr(d, 'rssi', '?')}")


async def find(name_hint: str):
    devices = await BleakScanner.discover(timeout=10)
    matches = [d for d in devices if d.name and name_hint.lower() in d.name.lower()]
    if not matches:
        print(f"没找到名字包含 {name_hint!r} 的设备，先跑 scan 看看。")
        return None
    if len(matches) > 1:
        print("匹配到多台，使用第一台：")
        for d in matches:
            print("  ", d.name, d.address)
    return matches[0]


async def cmd_dump(args):
    device = await find(args.name)
    if not device:
        return
    async with BleakClient(device) as client:
        print(f"已连接 {device.name} ({device.address})")
        for service in client.services:
            print(f"\n[service] {service.uuid}  {service.description}")
            for ch in service.characteristics:
                props = ",".join(ch.properties)
                print(f"  [char] {ch.uuid:<40} [{props}]  handle={ch.handle}")
                for desc in ch.descriptors:
                    print(f"      [desc] {desc.uuid} handle={desc.handle}")
        if args.seconds:
            print(f"\n保持连接 {args.seconds} 秒，观察通知…")
            await asyncio.sleep(args.seconds)


async def cmd_watch(args):
    device = await find(args.name)
    if not device:
        return
    start = time.time()

    def on_notify(sender, data: bytearray):
        elapsed = time.time() - start
        print(f"[{elapsed:7.3f}] {sender.uuid if hasattr(sender, 'uuid') else sender}  {len(data):3d}B  {hexdump(data)}")

    async with BleakClient(device) as client:
        print(f"已连接 {device.name}，监听 {args.seconds} 秒…")
        for service in client.services:
            for ch in service.characteristics:
                if "notify" in ch.properties or "indicate" in ch.properties:
                    try:
                        await client.start_notify(ch, on_notify)
                        print(f"  订阅 {ch.uuid}")
                    except Exception as exc:  # noqa: BLE001
                        print(f"  订阅 {ch.uuid} 失败：{exc}")
        await asyncio.sleep(args.seconds)
        await client.stop_notify_all()


async def cmd_write(args):
    device = await find(args.name)
    if not device:
        return
    payload = bytes.fromhex(args.hex.replace(" ", "").replace(",", ""))
    async with BleakClient(device) as client:
        await client.write_gatt_char(args.char, payload, response=args.with_response)
        print(f"已写入 {args.char}: {hexdump(payload)}")
        if args.seconds:
            await asyncio.sleep(args.seconds)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("scan").set_defaults(func=cmd_scan)

    dump = sub.add_parser("dump")
    dump.add_argument("--name", required=True)
    dump.add_argument("--seconds", type=int, default=0)
    dump.set_defaults(func=cmd_dump)

    watch = sub.add_parser("watch")
    watch.add_argument("--name", required=True)
    watch.add_argument("--seconds", type=int, default=30)
    watch.set_defaults(func=cmd_watch)

    write = sub.add_parser("write")
    write.add_argument("--name", required=True)
    write.add_argument("--char", required=True, help="特征 UUID，如 FFC1")
    write.add_argument("--hex", required=True)
    write.add_argument("--with-response", action="store_true")
    write.add_argument("--seconds", type=int, default=3)
    write.set_defaults(func=cmd_write)

    args = parser.parse_args()
    try:
        asyncio.run(args.func(args))
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
