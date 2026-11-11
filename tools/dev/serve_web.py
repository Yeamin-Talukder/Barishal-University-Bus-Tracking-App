"""Serves the web preview build (build/web) for local development.

Python's built-in http.server ignores HTTP Range requests, which the map
needs to read tiles out of the PMTiles archive, so this adds them.

Usage (from the project root, after `flutter build web`):

    python tools/dev/serve_web.py [port]
"""

from __future__ import annotations

import os
import re
import sys
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WEB_ROOT = Path(__file__).resolve().parents[2] / "build" / "web"
RANGE = re.compile(r"bytes=(\d*)-(\d*)$")


class RangeRequestHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        header = self.headers.get("Range")
        path = self.translate_path(self.path)
        match = RANGE.match(header.strip()) if header else None
        if not match or not os.path.isfile(path):
            return super().send_head()

        size = os.path.getsize(path)
        start_text, end_text = match.groups()
        if start_text == "":
            # Suffix range: the last N bytes.
            start = max(size - int(end_text or 0), 0)
            end = size - 1
        else:
            start = int(start_text)
            end = min(int(end_text), size - 1) if end_text else size - 1
        if start > end or start >= size:
            self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
            return None

        handle = open(path, "rb")
        handle.seek(start)
        self._remaining = end - start + 1
        self.send_response(HTTPStatus.PARTIAL_CONTENT)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(self._remaining))
        self.end_headers()
        return handle

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "_remaining", None)
        if remaining is None:
            return super().copyfile(source, outputfile)
        self._remaining = None
        while remaining > 0:
            chunk = source.read(min(65536, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)

    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format, *args):  # noqa: A002 - signature from base
        if "error" in format.lower() or (args and str(args[1:2]) >= "['4"):
            super().log_message(format, *args)


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5600
    if not WEB_ROOT.is_dir():
        print(f"{WEB_ROOT} not found. Run `flutter build web` first.")
        return 1
    handler = partial(RangeRequestHandler, directory=str(WEB_ROOT))
    with ThreadingHTTPServer(("localhost", port), handler) as server:
        print(f"Serving {WEB_ROOT} at http://localhost:{port}")
        server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
