"""多线程分段下载器：突破单连接限速。用法: python download.py <url> <out> [parts]"""
import os
import sys
import threading
import time
import urllib.request

URL = sys.argv[1]
OUT = sys.argv[2]
PARTS = int(sys.argv[3]) if len(sys.argv) > 3 else 16

UA = {"User-Agent": "Mozilla/5.0"}


def probe():
    """用 Range: bytes=0-0 探测总大小与最终 URL"""
    req = urllib.request.Request(URL, headers={**UA, "Range": "bytes=0-0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        cr = r.headers.get("Content-Range", "")
        total = int(cr.split("/")[-1]) if "/" in cr else int(r.headers["Content-Length"])
        return r.geturl(), total


final_url, size = probe()
print(f"size={size/1048576:.1f} MB  parts={PARTS}", flush=True)

chunk = (size + PARTS - 1) // PARTS
done = [0] * PARTS
errs = []

# 预分配，保证并发写入偏移正确
with open(OUT, "wb") as f:
    f.truncate(size)


def worker(i):
    start = i * chunk
    end = min(start + chunk, size) - 1
    if start > end:
        return
    for attempt in range(5):
        try:
            req = urllib.request.Request(
                final_url, headers={**UA, "Range": f"bytes={start}-{end}"}
            )
            got = 0
            with urllib.request.urlopen(req, timeout=60) as r, open(OUT, "r+b") as f:
                f.seek(start)
                while True:
                    buf = r.read(65536)
                    if not buf:
                        break
                    f.write(buf)
                    got += len(buf)
                    done[i] = got
            if got == end - start + 1:
                return
        except Exception as e:  # noqa: BLE001
            done[i] = 0
            if attempt == 4:
                errs.append(f"part{i}: {e!r}")


threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(PARTS)]
t0 = time.time()
for t in threads:
    t.start()

while any(t.is_alive() for t in threads):
    time.sleep(1.0)
    got = sum(done)
    el = time.time() - t0
    speed = got / el / 1024 if el else 0
    print(f"\r{got/1048576:7.1f}/{size/1048576:.1f} MB  {speed:7.1f} KB/s", end="", flush=True)

for t in threads:
    t.join()

print()
if errs:
    print("FAILED:", *errs, sep="\n  ")
    sys.exit(1)
print(f"OK {os.path.getsize(OUT)} bytes in {time.time()-t0:.0f}s")
