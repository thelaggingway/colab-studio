# MiniMax H3 text-to-video (ComfyUI)

Licence: MiniMax H3 community licence (excludes use in the US, EU, UK and South Korea). No deepfakes of real people.

## Run it

```bash
amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 minimax-h3 60 60 A100 G4'
# waits for a free GPU, pulls ~42 GB with aria2, starts ComfyUI, forwards :8188, stops the GPU after 60 idle minutes
```

Add `L4` to the end of the GPU list to fall back when A100 and G4 are busy (`A100 G4 L4`); the section
below says what each card costs. Once the watchdog releases the GPU the service parks instead of exiting,
so stop it yourself with `amp orb service stop studio-h3`.

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

## L4 and T4 as fallbacks (2026-11-23, same recipe and clips, template prompt)

L4 was granted at once; T4 too (three sessions at the same time worked on this account). Same int8 diffusion model, nvfp4 text encoder and int8 video VAE as above.

| GPU | VRAM / RAM | Clip | Steps | s/step | Total | Rate | Units |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A100 40 GB | 40 / 83 GB | 864x480, 5.2 s | 20 | | 118 s | 6.73/hr | 0.22 |
| A100 40 GB | 40 / 83 GB | 1280x736, 10.1 s, turbo | 8 | 39 | 344 s | 6.73/hr | 0.64 |
| L4 | 23 / 52 GB | 864x480, 5.2 s | 20 | 12.8 | 371 s | 1.94/hr | 0.20 |
| L4 | 23 / 52 GB | 1280x736, 10.1 s, turbo | 8 | 133.5 | 1137 s (19 min) | 1.94/hr | 0.61 |
| T4 high-RAM | 15 / 52 GB | 864x480, 5.2 s | 20 | 199.8 | about 66 min, not run to the end | 1.57/hr | about 1.7 |
| T4 high-RAM | 15 / 52 GB | 864x480, 5.2 s, turbo | 8 | 221.4 | 1897 s (32 min) | 1.57/hr | 0.83 |

All three clips that ran to the end are H.264 with stereo AAC: 864x480 at 5.17 s (L4 and T4) and 1280x736 at 10.13 s (L4).

What each GPU does with the same files:

- **L4** runs both clips and is at the edge of its 23 GB: peak 22.3 GB VRAM, and 45 of 52 GB of system RAM because both the 20 GB diffusion model and the 15 GB text encoder stage in RAM. 1280x736 for 10 s is about its ceiling; larger or longer clips will spill to RAM and slow down further.
- **T4** runs the model but bf16 has no fused kernels on Turing, so ComfyUI warns `Mismatch dtype between input and weight: input dtype = float, weight dtype = c10::BFloat16, Cannot dispatch to fused implementation` and falls back to a slow path. It needs the high-RAM shape: the standard 12.7 GB machine cannot hold the 21 GB diffusion model plus the 15 GB text encoder. Start it with `COLAB_NEW_ARGS=--high-mem bash scripts/studio-up.sh t4test minimax-h3 10 15 T4`. Peak 14.6 GB VRAM, 45 of 52 GB RAM.
- No out-of-memory or unsupported-dtype failure happened on either card; the int8 weights and the nvfp4 text encoder load on Turing as well as Ada.

## Which GPU for which clip

- **1280x736, 10 s, turbo: A100/G4 when free, L4 when it is not.** L4 costs 0.61 units against 0.64 on A100 for the same clip, so the only price of falling back is wall time (19 min against 6). G4 stays the pick for anything bigger, because 736p already fills the L4.
- **864x480, 5 s: L4 is a fine default.** 6 min and 0.20 units, slightly cheaper than A100, and it leaves the A100 free for longer clips.
- **T4: emergency only.** 32 min and 0.83 units for the smallest clip, four times the L4 cost for the same output, and 17 times its time per step. A 1280x736 10 s clip would take about 5 hours and 8 units by scaling from L4's step times. Use it only when nothing else can be had.
- Rates were measured on the account with `colab usage`: A100 6.73, L4 1.94, T4 high-RAM 1.57 units/hour. Setup is cheap on both: L4 took 211 s from assignment to ComfyUI reachable, including the 42 GB pull (121 s).
