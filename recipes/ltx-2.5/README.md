# LTX-2.5 text-to-video (ComfyUI)

Licence: LTX-2 Community licence (Lightricks). Free to use for organisations under $10M annual revenue; above that you need a
commercial licence. Other terms apply, including no use to build a competing video model or product and Lightricks' acceptable-use
rules. Read the full text on https://huggingface.co/Lightricks/LTX-2.5 before using outputs commercially.
The Hugging Face repo is gated: accept the licence there once with the account that owns `HF_TOKEN`, and the token must be allowed to
read public gated repos (a fine-grained token needs that box ticked). Without that, downloads return HTTP 403.

## Run it

```bash
printf %s "$HF_TOKEN" | bash scripts/colab-ssh.sh h3 'umask 077; cat > /content/.hf_token'   # token for the gated repo, never printed
amp orb service start studio-h3 --command 'bash scripts/studio-up.sh h3 ltx-2.5 60 60 A100 G4'
```

On a VM that already runs ComfyUI (for example the H3 recipe), only pull the weights; ComfyUI sees new files without a restart:

```bash
bash scripts/colab-ssh.sh h3 'cat > /content/ltx_models.txt' < recipes/ltx-2.5/models.txt
bash scripts/colab-ssh.sh h3 'aria2c -q -x16 -s16 -j6 --auto-file-renaming=false --allow-overwrite=true --header="Authorization: Bearer $(cat /content/.hf_token)" -i /content/ltx_models.txt'
```

Then either load the "LTX-2.5: Text to Video" template (`video_ltx2_5_t2v`) in the ComfyUI UI, or queue `t2v-api.json`. It is the template's
subgraph flattened by hand into API format (node ids `405:<inner id>`), with prompt enhance off as in the template, set to the fox/forest
prompt at 10 s. Edit:

- `409` megapixels: 0.4 gives 832x448 output, 0.9 gives 1280x704 (see "Resolution" below)
- `405:362` duration in seconds (frames = seconds x 24 + 1); `405:361` frame rate
- `405:376` prompt; `405:339` seed (stage 1). Change the seed or prompt between runs, or ComfyUI returns the cached result.

```bash
python3 -c 'import json,urllib.request; p=json.load(open("recipes/ltx-2.5/t2v-api.json")); urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8188/prompt", json.dumps({"prompt":p}).encode(), {"Content-Type":"application/json"}))'
```

Output: `/content/ComfyUI/output/video/LTX_2.5_*.mp4`, also at `http://127.0.0.1:8188/view?filename=<name>&subfolder=video&type=output`.

The template is two-stage and distilled: 8 steps at half resolution, x2 latent spatial upscale, then 3 refine steps at full resolution,
euler_ancestral with fixed sigmas, CFG 1. Default files are int8 (transformer 21.5 GB, Gemma 4 12B text encoder 15.4 GB) and fit a
40 GB A100.

### Resolution

The selector's size is halved for stage 1 and must then be a multiple of 32, so heights round down: 0.9 MP (1280x736) gives 1280x704,
0.4 MP (864x480) gives 832x448.

## Measured (2026-11-23, Colab A100-SXM4-40GB, rate 6.73 units/hour, ComfyUI 0.46, templates 0.11.114)

| Step | Time | Units |
| --- | --- | --- |
| aria2 download of all 6 files (~45 GB) onto a VM already running ComfyUI | 138 s | ~0.26 |
| Fox prompt, 1280x704, 10.04 s (241 frames), cold (first load of all models) | 106 s | ~0.20 |
| Same prompt, new seed, warm (text encoding cached) | 61 s | ~0.11 |
| Template default prompt, 832x448, 5.04 s, warm | 21 s | ~0.04 |

Steps: stage 1 at 0.87 s/step (8 steps, 640x352 latent pass), stage 2 at 5.45 s/step (3 steps at 1280x704) for the 10 s clip;
about 0.82 s/step for both stages of the 5 s 832x448 clip. nvidia-smi showed 40.0 to 40.4 GB in use (all of it) during every run:
ComfyUI's dynamic VRAM loading fills the card, it did not slow down or fail. All clips have 48 kHz stereo AAC audio.

### Against MiniMax H3 (same prompt, same GPU)

| | MiniMax H3 (turbo 8-step) | LTX-2.5 (distilled) |
| --- | --- | --- |
| Generation, 10 s clip | 344 s (~0.64 units) | 106 s cold / 61 s warm (~0.20 / 0.11 units) |
| Resolution, length | 1280x736, 10.1 s | 1280x704, 10.04 s |
| Audio | stereo AAC | stereo AAC |

Quality on the fox storyboard (contact sheets in `.amp/in/artifacts/`): both clips show all four shots and the fox. H3 makes hard
cuts close to the timestamps (at 4.2, 7.0 and 8.8 s), has more saturated colour, more fine detail, and shows the birds in shot 1.
LTX-2.5 joins the shots with cross-dissolves rather than cuts (the fox fades in over the stream at about 6 s), uses a darker,
more filmic grade, shows no birds in the frames I sampled, and its fox stands still facing the camera on the log with little movement rather than stepping onto it. The fox is clean
(fur, eyes, paws). A second seed added a rounded black vignette around the frame. H3 is better on prompt adherence and detail;
LTX-2.5 is about 3 to 6 times faster.

## More clips (2026-11-23, same A100, 10 s each, stereo audio)

| Clip | Model | Time | Units | Prompt adherence |
| --- | --- | --- | --- | --- |
| product macro (earbud case) | LTX-2.5 | 61 s | 0.11 | Clean and sharp, but the lid never opens |
| rainy night market | LTX-2.5 | 62 s | 0.12 | Good; signs show unreadable made-up characters |
| stylised robot animation | LTX-2.5 | 60 s | 0.11 | Nice look; "tiny planet" became a dome, flower already open |
| knight vs dragon (timed storyboard) | MiniMax H3 | 342 s + ~2 min model reload | 0.87 | Four hard cuts; missed the leap, sparks and collapse |
| omelette (timed storyboard) | MiniMax H3 | 342 s | 0.64 | Followed the storyboard closely |

Takeaway: LTX-2.5 is about 3-6x faster and cheaper per clip and looks good, but often skips specific actions; MiniMax H3 follows
timed storyboards better. Switching between the two on one VM costs a model reload (about 2 minutes on A100).
