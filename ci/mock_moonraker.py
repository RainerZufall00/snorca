"""Minimal stand-in for the Snapmaker U1's Moonraker API, used by the UI test.

Implements the endpoints Snarwal calls. Uploaded files are stored in
--upload-dir so CI can check what the app sent. Standard library only.

  python3 ci/mock_moonraker.py --port 7125 --upload-dir /tmp/uploads
"""
import argparse
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE = {"state": "standby", "filename": "", "light": True, "fan": 0.0, "gcode": []}


def status():
    printing = STATE["state"] in ("printing", "paused")
    return {
        "print_stats": {
            "state": STATE["state"], "filename": STATE["filename"], "message": "",
            "print_duration": 600.0 if printing else 0.0,
            "info": {"current_layer": 12 if printing else None, "total_layer": 50 if printing else None},
        },
        "virtual_sdcard": {"progress": 0.24 if printing else 0.0},
        "toolhead": {"extruder": "extruder"},
        "extruder": {"temperature": 219.5 if printing else 24.0, "target": 220 if printing else 0},
        "extruder1": {"temperature": 24.0, "target": 0},
        "extruder2": {"temperature": 24.0, "target": 0},
        "extruder3": {"temperature": 24.0, "target": 0},
        "heater_bed": {"temperature": 60.0 if printing else 23.0, "target": 60 if printing else 0},
        "fan": {"speed": STATE["fan"]},
        "led cavity_led": {"color_data": [[0, 0, 0, 1 if STATE["light"] else 0]]},
        "print_task_config": {
            "filament_type": ["PLA", "PLA", "PLA", "PLA"],
            "filament_sub_type": ["Basic", "Basic", "Matte", "NONE"],
            "filament_vendor": ["Snapmaker", "Snapmaker", "Snapmaker", "Generic"],
            "filament_color_rgba": ["EDEDE8FF", "2A2A2AFF", "E8792BFF", "2F6FD6FF"],
            "filament_exist": [True, True, True, True],
        },
    }


def parse_multipart(body, content_type):
    boundary = re.search(r"boundary=([^;]+)", content_type).group(1).strip('"').encode()
    fields, files = {}, {}
    for part in body.split(b"--" + boundary):
        if b"\r\n\r\n" not in part:
            continue
        head, data = part.split(b"\r\n\r\n", 1)
        data = data[:-2] if data.endswith(b"\r\n") else data
        name = re.search(rb'name="([^"]+)"', head)
        filename = re.search(rb'filename="([^"]+)"', head)
        if not name:
            continue
        if filename:
            files[name.group(1).decode()] = (filename.group(1).decode(), data)
        else:
            fields[name.group(1).decode()] = data.decode()
    return fields, files


class Handler(BaseHTTPRequestHandler):
    upload_dir = "."

    def log_message(self, fmt, *args):
        sys.stdout.write("mock: " + (fmt % args) + "\n")
        sys.stdout.flush()

    def reply(self, payload, code=200):
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/printer/objects/query":
            self.reply({"result": {"eventtime": 1.0, "status": status()}})
        elif url.path == "/server/webcams/list":
            self.reply({"result": {"webcams": []}})
        elif url.path == "/server/files/metadata":
            self.reply({"result": {"estimated_time": 2400}})
        else:
            self.reply({"error": {"message": "not found"}}, 404)

    def do_POST(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""
        if url.path == "/server/files/upload":
            fields, files = parse_multipart(body, self.headers.get("Content-Type", ""))
            if "file" not in files:
                return self.reply({"error": {"message": "no file"}}, 400)
            name, data = files["file"]
            os.makedirs(self.upload_dir, exist_ok=True)
            with open(os.path.join(self.upload_dir, os.path.basename(name)), "wb") as f:
                f.write(data)
            started = fields.get("print") == "true"
            if started:
                STATE.update(state="printing", filename=name)
            print(f"mock: stored {name} ({len(data)} bytes), print={started}", flush=True)
            return self.reply({"result": {"item": {"path": name, "root": fields.get("root", "gcodes")},
                                          "print_started": started}}, 201)
        if url.path == "/printer/print/start":
            STATE.update(state="printing", filename=query.get("filename", [""])[0])
        elif url.path == "/printer/print/pause":
            STATE["state"] = "paused"
        elif url.path == "/printer/print/resume":
            STATE["state"] = "printing"
        elif url.path == "/printer/print/cancel":
            STATE["state"] = "cancelled"
        elif url.path == "/printer/gcode/script":
            script = query.get("script", [""])[0]
            STATE["gcode"].append(script)
            if script.startswith("SET_LED"):
                STATE["light"] = script.endswith("WHITE=1")
            if script.startswith("M106 S"):
                STATE["fan"] = int(script[6:]) / 255
        else:
            return self.reply({"error": {"message": "not found"}}, 404)
        self.reply({"result": "ok"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=7125)
    parser.add_argument("--upload-dir", default="uploads")
    args = parser.parse_args()
    Handler.upload_dir = args.upload_dir
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"mock moonraker on 127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
