# Prior art: existing Colab, notebook and ComfyUI setups for these models

What already exists for each model this repo plans to run, so a recipe starts from proven work
instead of a blank page. Checked 2026-11-23.

Every row was read, not just searched: stars, last push and licence come from the GitHub and Hugging
Face APIs on that date, and the "headless" column is my judgement after reading the install and launch
steps, not a claim by the project. "Headless" means it can run on a VM with no notebook UI, no
`ipywidgets`, no Gradio share link and no Drive mount prompt, driven over `colab ssh` or the ComfyUI
HTTP API. The test is our own: `recipes/minimax-h3/` plus `scripts/studio-up.sh`.

Read the tables as: **source** (what it is) · **what it gives us** · **metadata** (last push · stars ·
licence) · **GPU** it targets · **headless** · **reuse how**.

## The short version

- The single best source is **[Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates)**:
  the official workflow JSON for almost every model here, MIT licensed, updated daily. Vendoring one
  file beats writing a graph by hand, and it is the same graph the ComfyUI UI offers.
- **[berkeduruu/colab-studio](https://github.com/berkeduruu/colab-studio)** is the closest thing to this
  repo that already exists (Colab CLI + ComfyUI + L4 + per-mode model catalog). Its model catalog is a
  ready-made map of Comfy-Org file paths for H3, TRELLIS.2, YuE2, Qwen3-TTS and Qwen-Image. It is
  AGPL-3.0, so copy facts, not code.
- Four planned recipes (z-image, ace-step, speech, upscale) are mostly assembly: official template or
  CLI plus a `models.txt`. Two more (wan-5b, ltx-2.5) need real work on the model-selection and
  offload side.
- Nothing found here is built on `colab ssh` the way we use it except
  [ledoesnt/colab-comfyui-launcher](https://github.com/ledoesnt/colab-comfyui-launcher) and
  [0xming12/colab-h3-infinite-canvas](https://github.com/0xming12/colab-h3-infinite-canvas). Both are
  worth reading before writing more of our own session plumbing.

## General ComfyUI-on-Colab launchers and Colab-CLI tooling

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | Official ComfyUI workflow JSONs for every model below, plus benchmark and blueprint variants | 2026-11-23 · 1536★ · MIT | any | n/a (JSON) | Vendor `templates/<file>.json`, then export API format the way `t2v-api.json` was made |
| [berkeduruu/colab-studio](https://github.com/berkeduruu/colab-studio) | Whole product: Colab CLI + ComfyUI + local web UI + MCP server, L4-only. `station/models.default.toml` maps every workflow slot to a Comfy-Org repo/file | 2026-11-19 · 2★ · AGPL-3.0 | L4 24 GB | Yes (UI is local, VM is headless) | Copy the model file paths and slot layout (H3 `w6a8`, TRELLIS.2, YuE2, Qwen3-TTS folder tree, Qwen3.5-9B prompt enhancer). Read `server/workflows.py` for graph shapes. Do not copy AGPL code |
| [ledoesnt/colab-comfyui-launcher](https://github.com/ledoesnt/colab-comfyui-launcher) | Official `google-colab-cli` 0.7.4 + Drive model cache + SSH port forward + per-instance compute-unit budget guard + H3 API smoke test. Measured H3 on G4: 42.03 GB pulled in 405 s; Drive copy 792 s vs 387 s direct | 2026-11-22 · 1★ · MIT | G4 96 GB tested | Yes (terminal UI local, VM headless) | Its failure taxonomy (`capacity_unavailable`, `auth_required`, `kernel_busy`, `execution_timeout`, "did we send it?") is worth adopting in `studio-up.sh`. Skip its `--public` Cloudflare mode |
| [deluxebear/colabllm](https://github.com/deluxebear/colabllm) | CLI where one service = one notebook + one `.py`: `comfyui`, `qwen-image`, `flux-klein`, `qwen3-tts` (vLLM-Omni on L4), `minimax-h3-image`, `nemotron-transcribe` | 2026-11-23 · 16★ · MIT | L4 / G4 / A100 | Yes (CLI), default access via Cloudflare/FRP tunnels | Port the `vllm serve --omni` lines and per-service GPU defaults; ignore the tunnel layer |
| [FireTable/comfy-colab-kit](https://github.com/FireTable/comfy-colab-kit) | Wake-on-demand gateway in front of ComfyUI on Colab L4, cold start + auto shutdown, Cloudflare Access in front | 2026-11-12 · 140★ · MIT | L4 | Partly (needs its gate) | Cold-start and idle-shutdown patterns. Its public sharing conflicts with Colab policy for our use |
| [TizenryA/colab-gpu-studio](https://github.com/TizenryA/colab-gpu-studio) | Phone-first studio: backend creates a Colab GPU per job, runs ComfyUI or H3, then destroys the runtime by default | 2026-11-13 · 230★ · AGPL-3.0 | L4 | Yes | "Destroy the runtime when the job ends" as the default rather than the exception. AGPL: read only |
| [ekkonwork/free-comfyui-colab-pack](https://github.com/ekkonwork/free-comfyui-colab-pack) | Per-model ComfyUI notebooks with a GGUF quant picker and a VRAM/size table: `zimage_turbo`, `zimage_seedvr2`, `qwen_image_2512`, `qwen_image_edit_2511`, `flux2_klein9b_gguf` | 2026-10-06 · 20★ · MIT | T4 / L4 | Partly (notebook + tunnel) | The quant-vs-VRAM table is the best starting point for T4. Its Cloudflare/bore tunnels are a policy conflict |
| [scarletkc/colab-playground](https://github.com/scarletkc/colab-playground) | Desktop front end for the official CLI: accounts, cost guards, port forwarding, plugins | 2026-11-23 · 432★ · MIT | any | Yes | Not a recipe source. Useful reference for multi-account and cost-guard UX |
| [googlecolab/google-colab-cli](https://github.com/googlecolab/google-colab-cli) | The CLI itself; `colab run` is an ephemeral job runner (fresh VM, run a local script, fetch outputs, tear down) | 2026-11-23 · 2963★ · Apache-2.0 | any | Yes | Consider `colab run` for one-shot batch recipes (speech, upscale) instead of a held session with a forwarded port |
| [camenduru/comfyui-colab](https://github.com/camenduru/comfyui-colab) | The classic ComfyUI Colab notebook family | 2024-08-08 · 551★ · Unlicense | T4 | No | Stale (SD 1.5 era, no updates since 2024). Ignore |
| [CodeyNotFound/comfyui-Easy-Colab](https://github.com/CodeyNotFound/comfyui-Easy-Colab) | ComfyUI + CivitAI/HF model finder + temporary public link | 2026-05-27 · 16★ · no licence file | T4 | No | Ignore: CivitAI pulls and a public tunnel |
| [renest-ai/renest-notebooks](https://github.com/renest-ai/renest-notebooks) | Restores a ComfyUI environment from a vendor "hand-off code" over a `trycloudflare` tunnel | 2026-11-10 · 0★ · Apache-2.0 | T4 / L4 / A100 | No | Ignore: vendor lock-in plus a public tunnel |

Two notes. `berkeduruu/colab-studio` has the same name as this repo and a very similar pitch, which is
worth knowing before publishing anything about ours. And the official CLI's `colab run` overlaps with
`scripts/studio-up.sh`: `run` is simpler for jobs that finish in one shot, while `studio-up.sh` is
right for interactive ComfyUI and for holding a GPU between jobs.

## MiniMax H3

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [MiniMax-AI/MiniMax-H3](https://github.com/MiniMax-AI/MiniMax-H3) (official) | SGLang serve example, vLLM recipe, links to the ComfyUI T2V/R2V templates, and the `h3-prompt-writing` skill with `base-en.txt` / `ref-en.txt` prompt guides | 2026-10-28 · 12168★ · custom H3 Community licence | datacentre (SGLang/vLLM) | Yes (server) | Install the prompt skill into `.agents/skills` (`npx skills add … --skill h3-prompt-writing`) so recipes get official prompt structure; use its template links |
| [0xming12/colab-h3-infinite-canvas](https://github.com/0xming12/colab-h3-infinite-canvas) | Colab CLI + SSH tunnel + ComfyUI on A100 80 GB; independently verified 5 s and 10 s H3 API workflows with AAC audio; also Qwen-Image-2.1 t2i/i2i graphs. Measured 52 s at 960×544 5 s, 253 s at 1344×768 10 s | 2026-11-14 · 3★ · MIT | A100 80 GB | Yes | Best source of working H3 API JSONs. Its 5 s graph is the right starting point for A100 40 GB; port `connect_colab_h3.sh` ideas into `scripts/colab-ssh.sh` |
| [dseditor/minimax-h3-colab](https://github.com/dseditor/minimax-h3-colab) | L4 notebooks: 37 GB model set, L4 timing (~4 min for a 10 s clip at 0.4 MP), optional Drive model cache, a web front end ("Toybox") over the ComfyUI API | 2026-11-05 · 59★ · no licence file | L4 24 GB | No (notebook cells, Colab secrets, Colab proxy link) | Reuse the L4 timings and the "T4 cannot run it (needs compute capability 8.0)" finding. Its default checkpoint is an unofficial int8 fine-tune (`OliviaRossi/Minimax-h3_Singularity-x-10Eros-Max_PRISM`) — do not adopt |

Flagged but not recommended: [FlashML-org/FreeVideo](https://github.com/FlashML-org/FreeVideo)
(Apache-2.0 code, 4599★, 2026-11-22) runs H3 in 8 GB VRAM through a third-party 8-step distilled model
(`OpenVDN/vdn-minimax-h3`) as a ComfyUI plugin. It is the only credible T4 path for H3, but the weights
are a derivative and the H3 Community licence (US/EU/UK/South Korea exclusion) still applies. Also
[nkxx188/ComfyUI-MiniMaxH3-Easy](https://github.com/nkxx188/ComfyUI-MiniMaxH3-Easy) (MIT, 929★,
2026-11-13) is a single compact T2V/I2V/FLF/ref workflow if the official template feels heavy, and
[LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler](https://github.com/LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler)
(MIT, 860★, 2026-11-10) upscales in latent space to avoid the 24-channel VAE decode.

## LTX-2.5 and LTX-2.3

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Lightricks/LTX-2](https://github.com/Lightricks/LTX-2) (official) | Python inference and LoRA trainer: `uv sync --extra natten`, `hf download`, then `python -m ltx_pipelines.distilled …` with `--quantization fp8-cast --offload {cpu,disk}` | 2026-11-19 · 10366★ · Apache-2.0 code, LTX-2.x Community model licence | 32 GB+ bf16; offload for less | Yes (pure CLI) | The cleanest ltx-2.5 path: no ComfyUI, no graph export. Use it if ComfyUI's int8 route disappoints. Download is ~66 GiB bf16 |
| [wildminder/awesome-ltx2](https://github.com/wildminder/awesome-ltx2) | Curated table of every LTX-2.x file with exact HF path and size: int8 ConvRot transformer 21.5 GB, nvfp4 18.72 GB, Gemma 4 12B encoders, distilled LoRA 8.9 GB, spatial/temporal upscalers, GGUF quants | 2026-11-13 · 605★ · no licence file | all tiers | n/a (list) | Build `models.txt` from it: int8 for L4/A100, GGUF for T4. Watch its warning that the 2.3 x2 1.0 upscaler was deleted upstream |
| [Lightricks/ComfyUI-LTXVideo](https://github.com/Lightricks/ComfyUI-LTXVideo) | Custom nodes plus example workflows for 2.3 and 2.5: single/two-stage, IC-LoRA (depth, pose, HDR, dub-it, spatial upscale), audio-only T2A | 2026-11-12 · 4276★ · NOASSERTION | 32 GB claimed | Yes if driven through the API | Vendor the 2.5 single-stage distilled workflow; install via ComfyUI Manager. Check the licence before copying node code |

Cross-check with the Comfy-Org templates `video_ltx2_5_t2v.json`, `video_ltx2_5_i2v.json`,
`video_ltx2_5_flf2v.json`, `video_ltx2_5_dfr_i2v.json` and, for 2.3, `video_ltx2_3_*` (2026-11-23 ·
1536★ · MIT, the same source listed under General). Those are the graphs the ComfyUI UI shows, which
makes them safer than a hand-exported graph.

## Wan 2.2 (5B and 14B)

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `video_wan2_2_5B_ti2v.json` for TI2V-5B; `video_wan2_2_14B_t2v/i2v/flf2v/s2v/animate.json` for A14B | 2026-11-23 · 1536★ · MIT | 8 GB with offload | n/a | Vendor `video_wan2_2_5B_ti2v.json` as the wan-5b recipe graph |
| [Wan-Video/Wan2.2](https://github.com/Wan-Video/Wan2.2) (official) | Reference implementation, model cards, VRAM/speed numbers, LoRA guidance | 2026-09-21 · 18858★ · Apache-2.0 | 4090-class and up | Yes (`generate.py`) | Reference for the A14B offload flags and for the 5B "runs at 8 GB with offload" claim |
| [Square-Zero-Labs/Wan2GP-on-Colab](https://github.com/Square-Zero-Labs/Wan2GP-on-Colab) | T4 notebook for Wan2GP (Gradio): reuses the runtime's PyTorch, installs with `uv`, drops `xformers`, warns that 15 GB T4 only manages 5B FastWan at 480p | 2026-11-12 · 210★ · Apache-2.0 | T4 15 GB | No (Gradio + share link) | Port the "reuse Colab's torch, `uv` install, skip `xformers` on T4" steps into `remote.sh`. Not the Gradio part |

For the 14B, [ostris/ai-toolkit](https://github.com/ostris/ai-toolkit) trains LoRAs on Wan 2.2 A14B and
is the better route than fighting inference VRAM.

## HunyuanVideo 1.5

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Tencent-Hunyuan/HunyuanVideo-1.5](https://github.com/Tencent-Hunyuan/HunyuanVideo-1.5) (official) | `generate.py` CLI, step-distilled 480p I2V (8 or 12 steps, 75 s on a 4090), in-repo `ComfyUI/README.md`, Diffusers support, LoRA training code | 2026-04-10 · 4615★ · Tencent Hunyuan Community (excludes EU/UK/South Korea) | 4090-class, 14 GB with offload | Yes | Port `--enable_step_distill` and the 480p distilled settings; follow the in-repo ComfyUI guide rather than a blog |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `video_hunyuan_video_1.5_720p_t2v.json`, `video_hunyuan_video_1.5_720p_i2v.json` | 2026-11-23 · 1536★ · MIT | 720p needs RAM | n/a | Vendor the 480p/720p graph and drop resolution for T4 |
| [Zehong-Ma/ComfyUI-MagCache](https://github.com/Zehong-Ma/ComfyUI-MagCache) | Training-free caching, 1.7× on HunyuanVideo 1.5 at 20 steps | 2025-11-27 · 275★ · Apache-2.0 | all | Yes | Cheap speedup if T4 timing is marginal |

Also relevant: Wan2GP claims 6 GB for HunyuanVideo 1.5 with an 8-step LoRA accelerator, which is the
only T4-friendly number found; treat it as a lead, not a measurement.

## Kandinsky 6.0 Lite

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [kandinskylab/kandinsky-6](https://github.com/kandinskylab/kandinsky-6) (official) | `just setup`, `just download pro-distill`, `just generate '<prompt>'`; Lite Distill 5 s clip: 173.7 s on a 16 GB 5060 Ti, 68 s on a 4090, 78.6 s on A100 80 GB. Also vLLM-Omni, SGLang and FastVideo paths | 2026-11-08 · 325★ · MIT | 16 GB works | Yes | Best fit for a headless recipe: `remote.sh` becomes `just setup && just download lite-distill && just generate`. Needs `uv` and `just` on the VM |
| [T8mars/Comfyui-Kandinsky-T8](https://github.com/T8mars/Comfyui-Kandinsky-T8) | Native ComfyUI nodes for Lite / Lite Distill / Pro Distill, single-file int8 ConvRot, PiFlow | 2026-10-08 · 7★ · MIT | 16 GB | Yes | Use if the recipe should stay ComfyUI-shaped like the others; otherwise skip |
| [ComfyUI registry node `kandinsky6`](https://registry.comfy.org/nodes/kandinsky6) | Registry install (`comfy node install kandinsky6`) via ComfyUI Manager, so no template is needed; v1.0.2 adds Lite Distill support | 2026-10-08 (v1.0.2) · 354★ · MIT (kandinskylab) | 16 GB | Yes | The node route is what `docs/workflows.md` already assumes |

Kandinsky has no core Comfy-Org template (only `image_kandinsky5_*` and `video_kandinsky5_*` exist), so
this is the one video recipe where the official Python path is simpler than the ComfyUI path.

## Z-Image Turbo

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `image_z_image_turbo.json` and `image_z_image_turbo_int8.json`, plus control/depth/pose blueprints | 2026-11-23 · 1536★ · MIT | 16 GB | n/a | Vendor `image_z_image_turbo.json`; this is the z-image recipe graph |
| [Tongyi-MAI/Z-Image](https://github.com/Tongyi-MAI/Z-Image) (official) | Diffusers pipeline usage, 8 NFE, no CFG, "fits in 16 GB", benchmark results | 2026-02-09 · 12186★ · Apache-2.0 | 16 GB | Yes (Diffusers) | Reference for sampler settings; the ComfyUI route is faster to stand up |
| [ekkonwork/free-comfyui-colab-pack](https://github.com/ekkonwork/free-comfyui-colab-pack) | GGUF quant picker with a size/VRAM table, auto-quant by VRAM, per-model `workflow.json` that gets patched to the chosen filenames | 2026-10-06 · 20★ · MIT | T4 | Partly | Copy the quant table and the "patch workflow filenames at runtime" trick for the T4 variant |

Model files are already listed in `docs/workflows.md` (`Comfy-Org/Z-Image-Turbo`, bf16 11.7 GB or int8
5.9 GB, `qwen_3_4b` encoder, `ae` VAE).

## Qwen-Image-2512 and Qwen-Image-Edit-2511

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `image_qwen_Image_2512.json`, `image_qwen_image_2512_with_2steps_lora.json`, `image_qwen_image_edit_2511.json`, `image_qwen_image_edit_2511_int8.json` | 2026-11-23 · 1536★ · MIT | 24 GB at fp8/int8 | n/a | Vendor the int8 edit graph and the 2-step-LoRA T2I graph; they are the cheap variants |
| [berkeduruu/colab-studio](https://github.com/berkeduruu/colab-studio) | Exact Comfy-Org int8 file names for the Qwen family, plus a Qwen3.5-9B prompt-enhancer slot | 2026-11-19 · 2★ · AGPL-3.0 | L4 | Yes | Copy the file paths and the prompt-enhancer idea (two encoder files, t2i and i2i) |
| [QwenLM/Qwen-Image](https://github.com/QwenLM/Qwen-Image) (official) | Diffusers usage, prompt guide, 2512 model card links | 2026-02-10 · 8493★ · Apache-2.0 | 24 GB+ | Yes | Prompt guidance only; ComfyUI is the better runner here |

Also [ekkonwork/free-comfyui-colab-pack](https://github.com/ekkonwork/free-comfyui-colab-pack) has
`qwen_image_2512` and `qwen_image_edit_2511` notebooks if the template needs a sanity check.

## FLUX.2 Klein

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `image_flux2_klein_text_to_image.json`, `image_flux2_klein_image_edit_4b_base.json`, `image_flux2_klein_image_edit_4b_distilled.json`, plus 9B variants | 2026-11-23 · 1536★ · MIT | 13 GB | n/a | Vendor the 4B distilled edit graph: this is the T4 editing path in `docs/workflows.md` |
| [ostris/ai-toolkit](https://github.com/ostris/ai-toolkit) | Training support for `FLUX.2-klein-base-4B` and `-9B`, plus Qwen-Image, Z-Image, Wan 2.2 | 2026-11-18 · 12700★ · MIT | 24 GB | Yes | Fine-tuning recipe base if we ever train Klein LoRAs |
| [deluxebear/colabllm](https://github.com/deluxebear/colabllm) | `flux-klein` service: vLLM-Omni on L4 with `--variant fp8r` | 2026-11-23 · 16★ · MIT | L4 / G4 / H100 | Yes | Serve line only, and note it targets **FLUX 3** Klein (5.6B, Kommunity licence), not FLUX.2 Klein 4B |

Do not mix these up: FLUX.2 Klein 4B is Apache-2.0 and has ComfyUI templates; FLUX 3 Image Klein is a
newer 5.6B model under the FLUX Kommunity licence (non-commercial with a commercial-output exception).
FLUX.2 **dev** is gated and non-commercial, as `docs/workflows.md` already says.

## Upscaling: SeedVR2 and Real-ESRGAN

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [numz/ComfyUI-SeedVR2_VideoUpscaler](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler) | ComfyUI nodes **and** a standalone multi-GPU CLI: `--chunk_size` streaming for long video, `--video_backend ffmpeg --10bit`, model caching, batch directory mode. Its own guidance: 8 GB with GGUF Q4 + BlockSwap, 12-16 GB at fp8, 24 GB+ for fp16 | 2025-12-24 · 3005★ · Apache-2.0 | 8-24 GB | Yes (CLI) | Use the CLI for the upscale recipe: no ComfyUI server needed for a batch pass over `outputs/`. Last push is a year old, but ComfyUI core now ships SeedVR2 natively |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `utility_seedvr2_3b_int8_upscale_video.json`, `utility_seedvr2_7b_int8_upscale_image.json`, `utility_seedvr2_video_upscale.json` | 2026-11-23 · 1536★ · MIT | 12-16 GB | n/a | Vendor the 3B int8 video graph, which matches the model files in `docs/workflows.md` |
| [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) | The 2×/4× fallback for a plain resample with no restoration | 2024-08-06 · 37621★ · BSD-3-Clause | any | Yes | Keep as fallback only; no dedicated Comfy-Org template exists, so it runs through ComfyUI's generic upscale-model nodes |

SeedVR2 also has Colab notebooks in the wild (`mikana0918`, `BilalSardar009/SEEDVR-Upscaling-360-videos`)
but they are single-purpose and unmaintained; the CLI above is better.

## Music: ACE-Step 1.5 and YuE

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [ace-step/ACE-Step-1.5](https://github.com/ace-step/ACE-Step-1.5) (official) | `uv sync`, then `uv run acestep-api` (REST on :8001) or the `acestep` CLI. 2B turbo under 4 GB VRAM, XL ≥12 GB with offload; LoRA from 8 songs in ~1 h on a 3090 | 2026-11-08 · 15106★ · MIT | T4 and up | Yes | The ace-step recipe should be this REST API, not ComfyUI: one `uv sync`, one server, JSON in, audio out |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `audio_ace_step_1_5_checkpoint.json` (AIO checkpoint), `audio_ace_step1_5_xl_turbo.json`, split-checkpoint variants | 2026-11-23 · 1536★ · MIT | 4-20 GB | n/a | Vendor the AIO checkpoint graph if the recipe should stay ComfyUI-shaped like `minimax-h3` |
| [multimodal-art-projection/YuE](https://github.com/multimodal-art-projection/YuE) | YuE2: `pip install .`, 24 GB VRAM, 48 kHz stereo, official Comfy-Org workflow `audio_yue2_text2music.json` | 2026-11-01 · 13689★ · Apache-2.0 code, **CC BY-NC 4.0 weights** | 24 GB | Yes | Only for non-commercial work. Not a drop-in for ACE-Step |

ACE-Step is the cheapest useful output in the whole plan and the official API removes the usual Gradio
dependency. Community Colab notebooks (`arlinamid/ace-step-colab`, MIT, T4; `AICHUCKY/…`) are one-offs
and add nothing over the official CLI.

## Speech to text: Qwen3-ASR, Whisper, Parakeet

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [QwenLM/Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) (official) | `pip install -U qwen-asr` (transformers or vLLM backend), batch inference, streaming, `Qwen3-ForcedAligner` timestamps, official Docker image | 2026-06-26 · 3937★ · Apache-2.0 | 4.5 GB bf16; use fp16 on T4 | Yes | The speech recipe's ASR half: one pip package, batch over a folder, JSON out |
| [SYSTRAN/faster-whisper](https://github.com/SYSTRAN/faster-whisper) | CTranslate2 Whisper, CLI and Python API, int8 on any GPU or CPU | 2026-11-12 · 26960★ · MIT | T4 / CPU | Yes | The compatibility fallback when Qwen3-ASR misbehaves on a T4 |
| [m-bain/whisperX](https://github.com/m-bain/whisperX) | Word-level timestamps and diarization on top of faster-whisper | 2026-11-21 · 25621★ · BSD-2-Clause | T4 | Yes | Add only when subtitles need word timing or speakers |

Parakeet is the weakest link: it needs NVIDIA NeMo, which is a heavy install on Colab, and the
available Colab material is stale ([camenduru/parakeet-rnnt-colab](https://github.com/camenduru/parakeet-rnnt-colab),
2024, no licence) or partial ([SoundsGoodAI/fast-gpu-asr](https://github.com/SoundsGoodAI/fast-gpu-asr),
Apache-2.0, 46★, batched Zipformer/Parakeet). Treat Parakeet as an optimisation, not the first path.

## Text to speech: Qwen3-TTS, Chatterbox, Kokoro

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) (official) | `pip install -U qwen-tts`, batch generation, voice clone from ~3 s, voice design, vLLM usage section, FlashAttention-2 notes | 2026-03-17 · 14607★ · Apache-2.0 | 4.6 GB peak | Yes | The TTS half of the speech recipe; batch API in one process |
| [deluxebear/colabllm](https://github.com/deluxebear/colabllm) | Working vLLM-Omni two-stage Qwen3-TTS on L4: server on :8000, auxiliary GPU worker on :8001, all four official workflows | 2026-11-23 · 16★ · MIT | L4 | Yes | Copy the two-stage `vllm serve --omni` layout and GPU-memory split if we want a long-lived TTS endpoint instead of a batch script |
| [remsky/Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) | OpenAI-compatible Kokoro-82M server, CPU or GPU | 2026-11-21 · 5728★ · Apache-2.0 | CPU | Yes | Narration path that costs no GPU units at all |

Chatterbox is retired: its own README says "as of August 2026, Chatterbox is retired research and is no
longer maintained", though ComfyUI still ships `audio-chatterbox_tts.json`. That confirms the
`docs/workflows.md` call to leave it alone.

## TRELLIS.2

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) | `3d_pixal3d_trellis2_image_to_model.json` (TRELLIS.2 and Pixal3D share the graph) | 2026-11-23 · 1536★ · MIT | 14 GB int8 | n/a | Vendor this graph; it is the L4/T4 path |
| [microsoft/TRELLIS.2](https://github.com/microsoft/TRELLIS.2) (official) | `setup.sh` with flash-attn, cumesh, o-voxel, nvdiffrast; Gradio `app.py`; says 24 GB minimum and H100-tested | 2026-07-10 · 13173★ · MIT | 24 GB | Partly (Gradio app, but callable in Python) | Reference only: the official install is heavy and wants 24 GB. Use ComfyUI plus the int8 files |
| [berkeduruu/colab-studio](https://github.com/berkeduruu/colab-studio) | Working L4 slot map: `trellis_2_int8_convrot`, `dino_v3_vit_l`, shape and texture VAEs, plus BiRefNet for background removal | 2026-11-19 · 2★ · AGPL-3.0 | L4 | Yes | Copy the five-file list including BiRefNet, which `docs/workflows.md` does not mention |

[visualbruno/ComfyUI-Trellis2](https://github.com/visualbruno/ComfyUI-Trellis2) (MIT, 892★, 2026-09-25)
is a wrapper if the core template needs a feature it lacks.

## Fine-tuning: Unsloth, ai-toolkit, musubi-tuner

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [unslothai/notebooks](https://github.com/unslothai/notebooks) | 250+ notebooks (Qwen3.5, Gemma 4, gpt-oss, Llama, Phi, TTS, GRPO/DPO) with data prep, training and inference in each | 2026-11-23 · 5834★ · LGPL-3.0 | T4 16 GB and up | Partly (cells are plain Python; convert to a script) | Convert the relevant notebook's cells into a `remote.sh` batch job. Do not vendor the notebooks wholesale |
| [ostris/ai-toolkit](https://github.com/ostris/ai-toolkit) | YAML-driven trainer for FLUX.1/2/3 Klein, Qwen-Image 2512/2.1, Z-Image Turbo, Wan 2.1/2.2, LTX-2/2.3/2.5, MiniMax-H3 and H3-Image | 2026-11-18 · 12700★ · MIT | 24 GB | Yes | Best base for image, Wan and H3 LoRA recipes: one YAML per model |
| [kohya-ss/musubi-tuner](https://github.com/kohya-ss/musubi-tuner) | LoRA training for HunyuanVideo, Wan 2.1/2.2, FLUX.2 dev/klein, Qwen-Image, Z-Image, **MiniMax-H3**, Kandinsky 5; 12 GB image / 24 GB video; `--convrot_int8` for GPUs without fp8 | 2026-10-31 · 2148★ · **no licence file** | 12-24 GB | Yes | The wider model list of the two, and the one with the T4-friendly int8 path. Its missing licence is a flag before vendoring any code |

The `--convrot_int8` option matters for T4: it halves frozen-weight VRAM and is faster than fp8 on
pre-Ada cards, which is the same trick the Comfy-Org int8 files use for inference.

## vLLM batch inference

| Source | What it gives us | Metadata | GPU | Headless | Reuse how |
| --- | --- | --- | --- | --- | --- |
| [vLLM-Omni](https://github.com/vllm-project/vllm-omni) + [recipes.vllm.ai](https://recipes.vllm.ai/) + [supported models](https://docs.vllm.ai/projects/vllm-omni/en/latest/models/supported_models) | Official `vllm serve <model> --omni` lines for image/video/audio models, with variant flags such as `--variant fp8r` and per-stage overrides. The site and docs publish from this repo's `recipes/` | 2026-11-23 · 7920★ · Apache-2.0 | H100/H200/B200 class | Yes | Use for the LLM batch recipe and for Qwen3-ASR/TTS serving. Its media recipes assume 80 GB cards, so not for L4/T4 |
| [dinhqhuy7/notebook-model-host](https://github.com/dinhqhuy7/notebook-model-host) | Per-model vLLM notebooks with a model-size table per Colab GPU, plus a key-protected OpenAI-compatible proxy | 2026-11-14 · 3★ · MIT | T4 / L4 / A100 | Partly (notebook + tunnel) | Reuse the "which model fits which Colab GPU" table and the vLLM launch cells; drop the Cloudflare tunnel |
| [deluxebear/colabllm](https://github.com/deluxebear/colabllm) | `colabllm gateway`: a local OpenAI/Anthropic-compatible aggregate gateway in front of several Colab services | 2026-11-23 · 16★ · MIT | any | Yes | Only if we later want several GPUs behind one endpoint |

## Hugging Face Spaces (reference only)

Spaces are hosted Gradio demos, so none of them is something we can run on our own VM. They are still
useful for checking expected quality and inference parameters before writing a recipe.

| Space | Likes | Last modified | Licence | Note |
| --- | --- | --- | --- | --- |
| [Tongyi-MAI/Z-Image-Turbo](https://huggingface.co/spaces/Tongyi-MAI/Z-Image-Turbo) | 1944 | 2026-05-22 | Apache-2.0 | Official Z-Image demo |
| [mrfakename/Z-Image-Turbo](https://huggingface.co/spaces/mrfakename/Z-Image-Turbo) | 3964 | 2026-10-15 | not declared | Fastest community demo; good baseline for latency expectations |
| [Lightricks/LTX-2-3](https://huggingface.co/spaces/Lightricks/LTX-2-3) | 507 | 2026-11-02 | not declared (model: LTX-2.x Community) | Official LTX-2.3 demo |
| [ACE-Step/Ace-Step-v1.5](https://huggingface.co/spaces/ACE-Step/Ace-Step-v1.5) | 600 | 2026-04-02 | MIT | Official music demo |
| [Qwen/Qwen3-TTS](https://huggingface.co/spaces/Qwen/Qwen3-TTS) | 2429 | 2026-06-09 | Apache-2.0 | Official TTS demo |
| [Qwen/Qwen3-ASR-Demo](https://huggingface.co/spaces/Qwen/Qwen3-ASR-Demo) | 267 | 2025-09-08 | Apache-2.0 | Official ASR demo |
| [microsoft/TRELLIS.2](https://huggingface.co/spaces/microsoft/TRELLIS.2) | 2455 | 2026-05-20 | MIT | Official 3D demo |
| [MiniMaxAI/MiniMax-H3-Turbo-Lora](https://huggingface.co/spaces/MiniMaxAI/MiniMax-H3-Turbo-Lora) | 580 | 2026-08-25 | not declared (model: H3 Community) | Official turbo-LoRA demo |

## Which planned recipes can be mostly assembled

Six of the planned recipes in `docs/workflows.md` already have most of their parts published. What is
left is our own session plumbing, which every recipe shares.

**`z-image` — almost entirely assembly.** Vendor `image_z_image_turbo.json` (or `_int8`), build
`models.txt` from the file list already in `docs/workflows.md`, and the only new work is the T4 GGUF
variant, where the ekkonwork quant table gives the starting point. No new code beyond `remote.sh`.

**`ace-step` — almost entirely assembly, and better without ComfyUI.** `uv sync` + `uv run acestep-api`
on :8001 from the official repo, one `models.txt` line for the AIO checkpoint if we prefer ComfyUI, and
a JSON request. This is the cheapest recipe to prove and the one where the official path is clearly
better than a graph.

**`speech` — mostly assembly.** `pip install -U qwen-asr` and `pip install -U qwen-tts` give both
halves; faster-whisper is the T4 fallback; Kokoro covers narration with no GPU at all. What we write is
the batch loop and the output layout, not model code. The open question is TTS throughput on T4, which
`docs/workflows.md` estimates at RTF 0.45 and needs measuring.

**`upscale` — mostly assembly.** SeedVR2's standalone CLI plus the 3B int8 files is a complete recipe;
the Comfy-Org 3B int8 video graph is the alternative if we want it to match `minimax-h3`'s shape. The
new work is choosing tile/batch settings for a 1280×736 H3 clip on L4.

**`wan-5b` — half assembly.** `video_wan2_2_5B_ti2v.json` and the Wan2.2 model cards cover the model;
the real work is the 24 GB fit (fp8 encoder, offload flags) and measuring whether 720p 5 s lands near
the 0.54-unit estimate on L4. Wan2GP's T4 notes help only for the 480p case.

**`ltx-2.5` — half assembly, with a real choice to make.** Two credible paths: the official
`ltx_pipelines.distilled` CLI with `--quantization fp8-cast --offload`, or ComfyUI with the 21.5 GB int8
transformer plus the `video_ltx2_5_*` template. The file list comes from `awesome-ltx2` either way. The
open question is system RAM: both paths need roughly 45 GB on a 16 GB card, so L4 is the target and a
standard T4 will not do.

`trellis-3d` is a close seventh: one template, five files, and a BiRefNet background-removal step that
`docs/workflows.md` does not yet mention.

## Licence and policy flags

**Do not copy code from:** [berkeduruu/colab-studio](https://github.com/berkeduruu/colab-studio) and
[TizenryA/colab-gpu-studio](https://github.com/TizenryA/colab-gpu-studio) (AGPL-3.0),
[unslothai/notebooks](https://github.com/unslothai/notebooks) (LGPL-3.0) and
[Comfy-Org/comfy-cli](https://github.com/Comfy-Org/comfy-cli) (GPL-3.0). Read them, reimplement what
they teach.

**No licence file, so ask before vendoring:** [dseditor/minimax-h3-colab](https://github.com/dseditor/minimax-h3-colab),
[kohya-ss/musubi-tuner](https://github.com/kohya-ss/musubi-tuner),
[wildminder/awesome-ltx2](https://github.com/wildminder/awesome-ltx2) (a list, so facts are fine) and
[Lightricks/ComfyUI-LTXVideo](https://github.com/Lightricks/ComfyUI-LTXVideo) (NOASSERTION).

**Unofficial mirrors and derivative weights, flagged:** the `OliviaRossi/Minimax-h3_Singularity-x-10Eros-Max_PRISM`
int8 checkpoint that `dseditor` uses; `OpenVDN/vdn-minimax-h3` behind FreeVideo; the `ChrisColeTech` LTX
mirrors in `awesome-ltx2`; and the uncensored `Noct-Q` Qwen-Image fine-tune that is `berkeduruu`'s
default. Our recipes should stay on Comfy-Org and model-author repos.

**Colab policy conflicts.** Nearly every notebook found reaches the UI through a public tunnel —
`trycloudflare.com`, `bore.pub`, FRP, ngrok, or the Colab proxy link. That is public serving of Colab
compute, which the FAQ disallows, and it is also how several of these projects expect to be used. Our
`colab ssh` + loopback port forward avoids it; the tunnels are the part to leave out. Drive mounting is
the other recurring pattern; we skip it by design and pay the re-download cost per session, which
`ledoesnt`'s measurements (405 s for 42 GB) suggest is cheap.

**Model licences that constrain recipes.** MiniMax H3 excludes the US, EU, UK and South Korea; LTX-2.x is
free under $10M revenue with no competing product; HunyuanVideo 1.5 excludes the EU, UK and South Korea;
YuE2 weights are CC BY-NC 4.0; FLUX.3 Klein is Kommunity-licensed while FLUX.2 Klein is Apache-2.0;
Chatterbox is retired. These match `docs/workflows.md`; nothing found here contradicts it.

## What not to reuse

- `camenduru/*` notebooks: the pattern that defined ComfyUI-on-Colab, but the repos are from 2024 and
  the model lists are SD 1.5 era.
- Any notebook whose launch cell ends in a tunnel: the setup cells can be useful, the launch cannot.
- `Colab Secrets` / `google.colab.userdata` code paths: we pass `HF_TOKEN` in the environment.
- Drive-cache copy scripts: they add minutes of copying to save a download that takes minutes.

## How this was checked

GitHub repo search, code search restricted to `.ipynb`, and direct README/catalog reads through the
GitHub API; Hugging Face Spaces through the HF API with the account token; `recipes.vllm.ai` and the
vLLM-Omni model list through web fetch. Stars, last push and licences are as of 2026-11-23 and will
drift. No GPU was started and no Colab session was created for this research.
