#!/usr/bin/env python3
"""Re-render one shot of a cheap draft (for example LTX-2.5) with MiniMax H3, starting from the draft's frame.

Runs on the agent machine against ComfyUI forwarded to 127.0.0.1:8188 with the H3 weights loaded
(recipes/minimax-h3). Needs ffmpeg/ffprobe locally. Writes <out>/<name>.mp4 and prints time and units.

  python3 recipes/draft-handoff/handoff.py --draft outputs/ltx-product.mp4 \
      --prompt-file shot.txt --last open-case.png --name product-lid --seconds 10

--last is optional but recommended for products and characters: without it H3 keeps the first frame
but drifts in shape and colour once the action starts. Make the last frame match the first frame's
framing (same position and size), changing only what the action changes.
"""
import argparse, json, os, subprocess, sys, tempfile, time, urllib.parse, urllib.request, uuid

HERE = os.path.dirname(os.path.abspath(__file__))


def call(url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def upload(base, path, name):
    boundary = uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{name}"\r\n'
            'Content-Type: image/png\r\n\r\n').encode() + open(path, "rb").read() + \
           f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n--{boundary}--\r\n'.encode()
    out = json.loads(call(f"{base}/upload/image", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}))
    return out["name"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--draft", required=True, help="draft video to start from (local mp4)")
    ap.add_argument("--at", type=float, default=0.0, help="time in the draft to take the first frame from (s)")
    ap.add_argument("--last", help="optional end-state image (png/jpg), same framing as the first frame")
    ap.add_argument("--prompt", help="timed storyboard prompt")
    ap.add_argument("--prompt-file", help="file holding the prompt")
    ap.add_argument("--seconds", type=float, default=10.0)
    ap.add_argument("--seed", type=int, default=int(time.time()) % 100000, help="new seed = new result; same seed+inputs = cached")
    ap.add_argument("--name", default="handoff")
    ap.add_argument("--out", default="outputs")
    ap.add_argument("--rate", type=float, default=6.73, help="units per hour of the GPU, for the report")
    ap.add_argument("--url", default="http://127.0.0.1:8188")
    a = ap.parse_args()
    prompt = a.prompt or (open(a.prompt_file).read() if a.prompt_file else None)
    if not prompt:
        sys.exit("give --prompt or --prompt-file (a timed storyboard plus an Audio: line works best)")

    tmp = tempfile.mkdtemp()
    first = os.path.join(tmp, "first.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(a.at), "-i", a.draft, "-frames:v", "1", first], check=True)
    w, h = map(int, subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                    "stream=width,height", "-of", "csv=p=0", first],
                                   capture_output=True, text=True, check=True).stdout.strip().split(","))
    w, h = w // 32 * 32, h // 32 * 32  # the H3 node takes multiples of 32

    p = json.load(open(os.path.join(HERE, "h3-flf2v-api.json")))
    node = p["140:131"]["inputs"]
    p["200"]["inputs"]["image"] = upload(a.url, first, f"{a.name}-first.png")
    if a.last:
        last = os.path.join(tmp, "last.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a.last, "-vf", f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h}", last], check=True)
        p["201"]["inputs"]["image"] = upload(a.url, last, f"{a.name}-last.png")
    else:
        node.pop("last_frame", None)
        del p["201"]
    node.update(prompt=prompt, width=w, height=h)
    p["140:133"]["inputs"]["value"] = a.seconds
    p["140:129"]["inputs"]["noise_seed"] = a.seed
    p["92"]["inputs"]["filename_prefix"] = f"video/{a.name}"

    pid = json.loads(call(f"{a.url}/prompt", json.dumps({"prompt": p}).encode(), {"Content-Type": "application/json"}))["prompt_id"]
    print(f"queued {pid}: {w}x{h}, {a.seconds}s, seed {a.seed}, last frame: {'yes' if a.last else 'no'}", flush=True)
    while True:
        h_ = json.loads(call(f"{a.url}/history/{pid}")).get(pid)
        if h_ and h_.get("status", {}).get("completed") is not None:
            break
        time.sleep(10)
    st = h_["status"]
    if st.get("status_str") != "success":
        sys.exit(f"failed: {json.dumps([m for m in st.get('messages', []) if m[0] == 'execution_error'])[:1500]}")
    ts = {m[0]: m[1].get("timestamp", 0) for m in st.get("messages", [])}
    secs = (ts.get("execution_success", 0) - ts.get("execution_start", 0)) / 1000
    vid = h_["outputs"]["92"]["images"][0]
    os.makedirs(a.out, exist_ok=True)
    dest = os.path.join(a.out, f"{a.name}.mp4")
    q = urllib.parse.urlencode({"filename": vid["filename"], "subfolder": vid["subfolder"], "type": "output"})
    open(dest, "wb").write(call(f"{a.url}/view?{q}"))
    print(f"done in {secs:.0f}s, about {secs * a.rate / 3600:.2f} units -> {dest}")


if __name__ == "__main__":
    main()
