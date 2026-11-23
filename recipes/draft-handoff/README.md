# Draft with LTX-2.5, fix the action with MiniMax H3

LTX-2.5 is fast and cheap and looks good, but it often skips the specific action a shot needs (a lid
opening, a flower blooming, a leap). MiniMax H3 follows timed storyboards better but costs about 6x more.
This recipe uses each for what it is good at. H3 cannot edit an existing video; it re-renders the shot
starting from a frame of the LTX draft.

## Workflow

1. **Storyboard.** Split the video into 5-10 s shots. Write each as a timed storyboard plus an `Audio:`
   line, for example `[0s-3s] slow orbit, the LED pulses. [3s-6s] the lid flips fully open ...`.
2. **Draft with LTX-2.5** (`recipes/ltx-2.5/`): 3-4 seeds per shot. 832x448 5 s is about 20 s and 0.04
   units on A100; 1280x704 10 s is about 60 s and 0.11 units. Pick the best framing, look and colour.
3. **Finish each shot.** If the draft already shows the action, keep it. If not, run `handoff.py` with
   the draft and the same storyboard. For products and characters, also give an end-state image with
   `--last` (see below).
4. **Batch by model.** Switching LTX <-> H3 on one VM reloads weights (about 2 minutes on A100). Do all
   drafts, then all H3 finals. Both models' weights (about 87 GB) fit on the VM disk together.
5. **Upscale and assemble** (planned: SeedVR2 recipe), then save to Drive (`scripts/drive-save.sh`).

Cost per 10 s shot: drafts ~0.15 units, H3 fix ~0.65 units, so ~0.8 for a fixed shot.

## Run it

ComfyUI with the H3 weights must be up and forwarded to 127.0.0.1:8188 (`recipes/minimax-h3/`).

```bash
python3 recipes/draft-handoff/handoff.py --draft outputs/ltx-product.mp4 --prompt-file shot.txt \
    --last open-case.png --name product-lid --seconds 10 --rate 6.73
```

It takes the first frame of the draft (or the frame at `--at <s>`), uploads it (and `--last`) with
ComfyUI's `/upload/image`, fills `h3-flf2v-api.json` (H3 image-to-video, 8-step turbo LoRA, size rounded
down to multiples of 32), queues it, waits, and saves `outputs/<name>.mp4` with time and units. Use a
new `--seed` per attempt: the same seed and inputs return ComfyUI's cached result in seconds.

`h3-flf2v-api.json` is the official `video_minimax_h3_i2v` template flattened to API format: `LoadImage`
nodes `200` and `201` feed `first_frame` and `last_frame` of `MiniMaxH3ImageToVideo` (`140:131`) directly,
with no resize node.

## Measured (2026-11-23, A100 40 GB, 6.73 units/h, product ad where the LTX lid never opened)

| Version | Time | Units | Result |
| --- | --- | --- | --- |
| LTX-2.5 draft, 1280x704 10 s | 61 s | 0.11 | Good look; lid never opens |
| H3, first frame only | 341 s | 0.64 | First frame kept (SSIM 0.905); lid opens on cue, earbuds visible. After opening, the case turns into a wider clamshell, the inside flips silver to black, earbuds become stem-style, the push-in crops the LED |
| H3, first + last frame | 352 s | 0.66 | Shape, black interior and round earbuds hold to the end; final frame matches the still (SSIM 0.87). Lid edge briefly morphs at ~2.5-3.75 s and opens a little early; the camera pushes in then pulls back to reach the still's framing instead of holding |

The last frame was made by editing the draft's first frame with an image model (Amp's painter tool):
"keep everything identical, change only: lid fully open, two earbuds visible". It came out slightly
higher and wider than the first frame, and H3 bridged that with camera motion.

## Rules of thumb

- Give a last frame for anything whose design must not drift (products, characters, logos you own).
- Make the last frame match the first frame's framing: same position and scale, changing only what the
  action changes. Otherwise H3 moves the camera to get there.
- Keep the storyboard timings; H3 lands its cuts and actions near them (within about 1 s).
- H3 audio can come out loud (this clip peaked at -0.5 dB). Normalise before publishing, for example
  `ffmpeg -i in.mp4 -c:v copy -af loudnorm=I=-16:TP=-1.5 out.mp4`. Listen to audio before using it;
  so far it has only been measured, not reviewed by ear.
- H3 licence excludes the US, EU, UK and South Korea; LTX-2.x Community licence has its own terms.
  No deepfakes of real people.

Untested next steps: a last frame aligned to the first frame's framing; `--at` from the middle of a
draft to extend it; the same hand-off on L4 (H3 fits; ~3x slower at the same units per clip).
