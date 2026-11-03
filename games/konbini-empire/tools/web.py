"""Export the Web build to build/web/: python tools/web.py [path to godot] [--artifact]

Fetches only the web export template out of Godot's 1.2 GB template archive (HTTP range
reads) when it isn't installed yet. --artifact makes a release build in build/artifact/ to
publish as a Claude Artifact, with tools/artifact.html as the page.
"""
import gzip, io, json, os, pathlib, re, subprocess, sys, urllib.request, zipfile

ARTIFACT = "--artifact" in sys.argv
args = [a for a in sys.argv[1:] if a != "--artifact"]
GODOT = args[0] if args else os.environ.get("GODOT", "godot")
ROOT = pathlib.Path(__file__).resolve().parent.parent
MODE = "release" if ARTIFACT else "debug"
TEMPLATE = f"web_nothreads_{MODE}.zip"


class Remote(io.RawIOBase):
    def __init__(self, url):
        r = self.get(url, 0, 0)
        self.url, self.size, self.pos = r.url, int(r.headers["Content-Range"].split("/")[1]), 0

    @staticmethod
    def get(url, a, b):
        return urllib.request.urlopen(urllib.request.Request(url, headers={"Range": f"bytes={a}-{b}"}))

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos

    def seek(self, off, whence=0):
        self.pos = [off, self.pos + off, self.size + off][whence]
        return self.pos

    def readinto(self, buf):
        n = min(len(buf), self.size - self.pos)
        if n <= 0:
            return 0
        data = self.get(self.url, self.pos, self.pos + n - 1).read()
        buf[:len(data)] = data
        self.pos += len(data)
        return len(data)


nums, status = re.match(r"(\d+(?:\.\d+)+)\.(\w+)", subprocess.run([GODOT, "--version"], capture_output=True, text=True).stdout.strip()).groups()
data = pathlib.Path(os.environ["APPDATA"]) / "Godot" if os.name == "nt" else pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share")) / "godot"
dest = data / "export_templates" / f"{nums}.{status}" / TEMPLATE
if not dest.exists():
    print(f"fetching {TEMPLATE} for Godot {nums}-{status}")
    url = f"https://github.com/godotengine/godot/releases/download/{nums}-{status}/Godot_v{nums}-{status}_export_templates.tpz"
    with zipfile.ZipFile(io.BufferedReader(Remote(url), 1 << 20)) as z:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(z.read("templates/" + TEMPLATE))

out = ROOT / "build" / ("artifact" if ARTIFACT else "web")
out.mkdir(parents=True, exist_ok=True)
(ROOT / "build" / ".gdignore").touch()
if not (ROOT / ".godot").exists():
    subprocess.run([GODOT, "--headless", "--path", str(ROOT), "--import"], check=True)
subprocess.run([GODOT, "--headless", "--path", str(ROOT), f"--export-{MODE}", "Web", str(out / "index.html")], check=True)
if ARTIFACT:
    # artifacts serve only web file types, at most 15 MB each: the engine goes gzipped, the pack as .wasm
    wasm = out / "index.wasm"
    wasm.write_bytes(gzip.compress(wasm.read_bytes(), 9))
    (out / "index.pck").replace(out / "index.pck.wasm")
    config = json.loads(re.search(r"const GODOT_CONFIG = (.*);", (out / "index.html").read_text(encoding="utf-8")).group(1))
    config["mainPack"] = "index.pck.wasm"
    config["fileSizes"]["index.pck.wasm"] = config["fileSizes"].pop("index.pck")
    (out / "index.html").write_text((ROOT / "tools" / "artifact.html").read_text(encoding="utf-8").replace("$GODOT_CONFIG", json.dumps(config)), encoding="utf-8")
print("exported", out / "index.html")
