# MiniMax H3 text-to-video (ComfyUI)

Licence: MiniMax H3 community licence (excludes use in the US, EU, UK and South Korea). No deepfakes of real people.

## Run it

```bash
amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4'
# waits for a free GPU, pulls ~42 GB with aria2, starts ComfyUI, forwards :8188, stops the GPU after 60 idle minutes
```

Then either load the "MiniMax H3: Text to Video" template in the ComfyUI UI, or queue `t2v-api.json`
(API format exported from a real run) after editing it:

- `115` megapixels: 0.4 = 864x480, 0.9 = 1280x736 (16:9)
- `140:133` duration in seconds; `140:139` true = 8-step turbo LoRA, false = 20 steps
- `140:131` prompt (timed storyboard plus an Audio line); `140:129` seed

```bash
python3 -c 'import json,urllib.request; p=json.load(open("recipes/minimax-h3/t2v-api.json")); urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8188/prompt", json.dumps({"prompt":p}).encode(), {"Content-Type":"application/json"}))'
```

Output: `/content/ComfyUI/output/video/*.mp4`, also at `http://127.0.0.1:8188/view?filename=<name>&subfolder=video&type=output`.

## Measured (2026-11-23, Colab A100-SXM4-40GB, rate 6.73 units/hour)

| Step | Time | Units |
| --- | --- | --- |
| Wait for a free A100/G4 | 10 to 30 min of 503s in the evening (UTC 15:30-16:00) | 0 |
| Setup: aria2 42 GB (128 s), pip, ComfyUI start | 6 min | ~0.67 |
| Clip 1: template defaults, 864x480, 5.2 s, 20 steps, cold model load | 118 s | ~0.22 |
| Clip 2: 1280x736, 10.1 s, 8-step turbo LoRA, 39 s/step | 344 s | ~0.64 |

Both clips have stereo AAC audio. Clip 2 used all 40 GB of VRAM, so longer or larger clips on A100 40 GB may spill to system RAM and slow down; use G4 (96 GB) when it is free.
For comparison, the source X post reported 3 min 16 s per 10 s act at 1280x704 on a G4 at 10.05 units/hour (about 0.55 units).
