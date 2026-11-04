"""Minimaler eSCL-Mock-Scanner zum Testen von einzugscan.sh (ohne echte Hardware).

Aufruf: python3 tests/mock_escl.py PORT SEITEN
Liefert pro Scanauftrag SEITEN JPEG-"Seiten" aus dem Einzug, danach 404.
"""
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGES = int(sys.argv[2]) if len(sys.argv) > 2 else 3
state = {"job": 0, "served": 0, "last_settings": ""}

CAPS = """<?xml version="1.0" encoding="UTF-8"?>
<scan:ScannerCapabilities xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
<pwg:Version>2.63</pwg:Version><pwg:MakeAndModel>Brother MFC-L2710DW series</pwg:MakeAndModel>
<scan:Platen/><scan:Adf><scan:AdfSimplexInputCaps/></scan:Adf>
</scan:ScannerCapabilities>"""

STATUS = """<?xml version="1.0" encoding="UTF-8"?>
<scan:ScannerStatus xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
<pwg:Version>2.63</pwg:Version><pwg:State>Idle</pwg:State>
<scan:AdfState>ScannerAdfLoaded</scan:AdfState></scan:ScannerStatus>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body=b"", ctype="text/xml", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/eSCL/ScannerCapabilities":
            return self.send(200, CAPS.encode())
        if self.path == "/eSCL/ScannerStatus":
            return self.send(200, STATUS.encode())
        if self.path == f"/eSCL/ScanJobs/{state['job']}/NextDocument":
            if state["served"] < PAGES:
                state["served"] += 1
                body = b"\xff\xd8FAKEJPEG job%d page%d\xff\xd9" % (state["job"], state["served"])
                return self.send(200, body, "image/jpeg")
            return self.send(404)
        self.send(404)

    def do_POST(self):
        if self.path == "/eSCL/ScanJobs":
            n = int(self.headers.get("Content-Length", 0))
            state["last_settings"] = self.rfile.read(n).decode()
            assert "<pwg:InputSource>Feeder</pwg:InputSource>" in state["last_settings"]
            sys.stderr.write(state["last_settings"])
            state["job"] += 1
            state["served"] = 0
            host = self.headers.get("Host")
            return self.send(201, extra={"Location": f"http://{host}/eSCL/ScanJobs/{state['job']}"})
        self.send(404)


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
