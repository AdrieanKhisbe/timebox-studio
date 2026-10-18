#!/usr/bin/env python3
"""Reproduce pinned alarm encoders without importing their Bluetooth stacks."""

import argparse
import ast
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
HASS_SHA256 = "3ec17896fb782bb3978ef38df3a68773ef6db3fb5f490ea9f88672fadd2f2fc6"
ESP32_SHA256 = "be165f6d412e579c566ef640c23351f2457a4e7b2b361bcdcd2bcb85b7d46e77"


def source(path, checksum):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != checksum:
        raise ValueError(f"Unexpected source hash: {path}")
    return data.decode("utf-8")


def hass_encoder(text):
    methods = {"show_alarm", "_parse_frequency", "send_command", "checksum", "escape_payload", "make_message"}
    model = next(node for node in ast.parse(text).body if isinstance(node, ast.ClassDef) and node.name == "Divoom")
    nodes = [node for node in model.body if isinstance(node, ast.FunctionDef) and node.name in methods]
    if {node.name for node in nodes} != methods:
        raise ValueError("Pinned reference methods missing")
    namespace = {}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), "<pinned alarm methods>", "exec"), namespace)
    model_type = type("OfflineEncoder", (), {name: namespace[name] for name in methods})
    model_type.send_payload = lambda self, payload, **kwargs: self.make_message(payload)
    model_type.disconnect = lambda self: None
    instance = model_type()
    instance.socket = True  # send_command checks this sentinel; no socket is created.
    instance.escapePayload = False
    instance.COMMANDS = {"set alarm": 0x43}
    return instance


def esp32_payloads(text, cases):
    start = text.index("void Divoom::show_alarm(")
    end = text.index("\n}\n", start) + 2
    method = text[start:end]
    # Only the reviewed, hash-pinned encoder is compiled. The dummy command sink
    # prints bytes instead of sending or opening any transport.
    harness = r'''
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <string>
class Divoom {
public:
  struct { int command[1]; size_t count = 0; } commands;
  void command(int*, uint8_t* data, size_t length) {
    for (size_t i=0; i<length; ++i) std::printf("%02x%s", data[i], i+1==length ? "\n" : " ");
  }
  void show_alarm(uint8_t, char*, bool*, uint8_t, uint8_t, float, uint8_t);
};
'''
    calls = []
    for index, case in enumerate(cases):
        days = case["weekdays"]
        flags = ",".join("true" if day in (days or []) else "false" for day in ["sun", "mon", "tue", "wed", "thu", "fri", "sat"])
        calls.append(f"Divoom d{index}; bool w{index}[7] = {{{flags}}};")
        time = "nullptr"
        if case["time"] is not None:
            calls.append(f"char t{index}[] = {json.dumps(case['time'])};")
            time = f"t{index}"
        weekdays = f"w{index}" if days is not None else "nullptr"
        calls.append(f"d{index}.show_alarm({case['number']}, {time}, {weekdays}, {case['alarmMode']}, {case['triggerMode']}, {case['frequency'] or 0}, {case['volume']});")
    with tempfile.TemporaryDirectory(prefix="timebox-alarm-reference-") as directory:
        cpp = Path(directory) / "reference.cpp"
        binary = Path(directory) / "reference"
        cpp.write_text(harness + method + "\nint main() {\n" + "\n".join(calls) + "\n}\n")
        subprocess.run(["c++", "-std=c++11", str(cpp), "-o", str(binary)], check=True)
        return subprocess.check_output([str(binary)], text=True).splitlines()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hass-source", type=Path, required=True)
    parser.add_argument("--esp32-source", type=Path, required=True)
    args = parser.parse_args()
    fixtures = json.loads((ROOT / "docs/validation/fixtures/evo-alarm-reference.json").read_text())
    cases = fixtures["cases"]
    encoder = hass_encoder(source(args.hass_source, HASS_SHA256))
    cpp = esp32_payloads(source(args.esp32_source, ESP32_SHA256), cases)
    for case, payload in zip(cases, cpp, strict=True):
        inputs = {key: case[key] for key in ["number", "time", "weekdays", "alarmMode", "triggerMode", "frequency", "volume"]}
        packet = bytes(encoder.show_alarm(**inputs)).hex(" ")
        if packet != case["packet"] or payload != case["payload"]:
            raise ValueError(f"Fixture mismatch: {case['name']}: hass={packet}, esp32={payload}")
        print(f"PASS {case['name']}")
    print("Reference bytes agree. Firmware behavior has not been tested.")


if __name__ == "__main__":
    main()
