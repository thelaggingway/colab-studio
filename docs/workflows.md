# What to run on these GPUs

Which creative and ML workflows are practical on the Colab GPUs this account can get, which open model to use on each tier, and what it costs in units. Research date 2026-11-23. Repos, file sizes and gated status were checked against the Hugging Face API on that date with the account token; speeds and VRAM come from the linked sources.

Every figure below is marked:

- **†** measured by the linked source (not by this repo).
- **est.** my estimate, derived from the † figure and the GPU's relative throughput. Treat as ±50%.
- Units are arithmetic from the measured rates in `config/account.env` and the thread that measured them (A100 6.73, L4 1.6-2.0, T4 1.1-1.8, G4 10 units/hour). I use A100 0.112, L4 0.030, T4 0.024 units/minute.

The only workflow measured end to end in this repo is MiniMax H3 on A100 (`recipes/minimax-h3/`). Everything else here is a plan until a recipe proves it.

## Best pick per area per GPU

Units are per output: one 1024² image, one clip, one song, one audio hour, one 3D asset.

| Area | A100 40 GB | L4 24 GB | T4 16 GB |
| --- | --- | --- | --- |
| Image generation | **Z-Image Turbo** bf16, 0.008 u | **Z-Image Turbo** bf16, 0.006 u | **Z-Image Turbo** bf16, 0.010 u |
| Image, text-heavy or 2K | **Qwen-Image-2512** fp8, 0.065 u | **Qwen-Image-2512** fp8, 0.030 u | Qwen-Image-2512 GGUF Q4, 0.10 u |
| Image editing | **Qwen-Image-Edit-2511** fp8, 0.15 u | **FLUX.2 Klein 4B**, 0.005 u; Qwen-Edit int8, 0.09 u | **FLUX.2 Klein 4B**, 0.01 u |
| Video with sound | **MiniMax H3** int8, 0.64 u / 10 s † | **Kandinsky 6.0 Lite** distill, 0.11 u / 5 s | **Kandinsky 6.0 Lite** distill, 0.19 u / 5 s |
| Video, no sound | **Wan 2.2 TI2V-5B**, 0.9 u / 5 s 720p | **Wan 2.2 TI2V-5B**, 0.54 u | **HunyuanVideo 1.5** 480p distilled, 0.48 u |
| Upscaling (image + video) | **SeedVR2 7B** int8, 0.45 u / 10 s clip | **SeedVR2 3B** int8, 0.29 u | **SeedVR2 3B** int8, 0.46 u |
| Music and songs | Dropped: use Suno (see `docs/music-generation.md`) | Dropped | Dropped |
| Speech to text | **Qwen3-ASR 1.7B**, 0.10 u / audio hour | **Qwen3-ASR 1.7B**, 0.05 u | **Whisper large-v3-turbo** int8 or Qwen3-ASR 0.6B, 0.07 u |
| Text to speech | Qwen3-TTS 1.7B, 3.7 u / audio hour | **Qwen3-TTS 1.7B**, 0.45 u | **Qwen3-TTS 1.7B**, 0.65 u |
| Image to 3D | **TRELLIS.2** int8, 0.22 u | **TRELLIS.2** int8, 0.12 u | **TRELLIS.2** int8, 0.22 u |
| LLM batch | **Qwen3.5-27B** AWQ, 62 tok/s † | **Qwen3.6-35B-A3B** Q4, ~0.01 u / 1k output tokens | **Qwen3.5-4B** fp16, or gpt-oss-20b MXFP4 |
| Fine-tuning | QLoRA to 32B, image LoRA, Wan LoRA | QLoRA to 14B, Z-Image/Qwen LoRA, Wan I2V LoRA | QLoRA to 8B, Z-Image LoRA (tight) |

TTS and STT are cheaper per output on L4/T4 than on A100: they are small models that finish in minutes, and the A100's 3.7x unit rate is not repaid.

## Rates, and why L4 is often the cheap tier

| GPU | VRAM | Units/hour | Units/minute | What it is good at |
| --- | --- | --- | --- | --- |
| A100 40 GB | 40 GB, 1.55 TB/s | 6.73 † | 0.112 | Big models (20B+ image, 22-33B video), fast bf16 (no fp8 compute), 83 GB RAM |
| L4 24 GB | 24 GB, 300 GB/s | 1.6-2.0 | 0.030 | fp8 compute, bf16, 24 GB; the cheapest tier that runs most current models |
| T4 16 GB | 16 GB, 320 GB/s | 1.1-1.8 | 0.024 | No bf16, no fp8 compute; small models and quantised (GGUF/int8) work |
| G4 96 GB | 96 GB | ~10 | 0.167 | Only for models that need >40 GB, or to avoid offload on H3 |

A slow GPU can be cheaper than a fast one because units track time, not work. Wan 2.2 5B makes a 5 s 720p clip in about 8 min on A100 (0.9 units) but about 18 min on L4 (0.54 units). Use A100 when wall-clock matters or the model does not fit; use L4 for batch work that fits in 24 GB.

Three hardware facts change what runs where:

- **T4 has no bf16 and no fp8 compute.** bf16 checkpoints run in fp16 or with upcasting; fp8/int8 files still load but do not get the fast path. Prefer GGUF Q4-Q6, int8, or fp16 models on T4.
- **A100 has no fp8 compute either.** fp8 files save VRAM but ComfyUI converts each layer to 16-bit to compute, so fp8 on A100 is a memory trick, not a speed trick.
- **System RAM matters as much as VRAM on T4.** A standard Colab T4 VM has about 12.7 GB of RAM (high-RAM VMs have 51 GB), and ComfyUI offloads weights to RAM when they do not fit. Models that need 30-45 GB of RAM — LTX-2.5, Qwen-Image-2512 at GGUF, HunyuanVideo 1.5 at 720p — need a high-RAM T4 or should move to L4.

## Image generation

**Z-Image Turbo** (Tongyi-MAI, 6B, Apache 2.0) is the default. 8 steps, no CFG, strong English and Chinese text. Its card says it fits in 16 GB. ComfyUI has a native template and a Comfy-Org repack.

| File | Repo | Size † |
| --- | --- | --- |
| `z_image_turbo_bf16.safetensors` | `Comfy-Org/Z-Image-Turbo` | 11.7 GB |
| `z_image_turbo_int8_convrot.safetensors` | same | 5.9 GB |
| `qwen_3_4b.safetensors` (text encoder) | same | 7.7 GB |
| `ae.safetensors` (VAE) | same | 0.3 GB |

Speed: 3.8-3.9 s per 1024² image on RTX 4090, 21.3 GB peak VRAM (ComfyUI keeps all three models resident), 6.75 s on a 16 GB RTX 4070 Ti Super †. Estimates: A100 ~4 s, L4 ~12 s, T4 ~25 s.

**Qwen-Image-2512** (20B, Apache 2.0) when text rendering or 2K detail matters. ComfyUI has a native 2512 template. Needs fp8 or lower: the bf16 transformer alone is 39.0 GB †, so it does not fit A100 40 GB at bf16 alongside a 15.8 GB text encoder. fp8 transformer 19.5 GB + fp8 encoder 8.9 GB is 28.4 GB of files, but ComfyUI drops the encoder after reading the prompt, so a 24 GB L4 runs it (22 GB peak on a 24 GB 4090 †). 27 s per 1024² image on a 4090 at fp8 †; 75.7 s at 1328² on a 16 GB card with offload †. On T4 only with a GGUF Q4 build and enough RAM.

Do not plan around **FLUX.2 dev** (32B, gated `auto`, non-commercial licence): 33.8 GB main model plus a 17 GB encoder, 134-718 s per image on a 4090 †. **Qwen-Image-2.1** (Sep 2026) is open-weight but under the Qwen Research licence, not open source.

## Image editing

**Qwen-Image-Edit-2511** (Apache 2.0) is the quality pick: instruction editing, multi-image reference, character consistency, built-in LoRAs.

| File | Repo | Size † |
| --- | --- | --- |
| `qwen_image_edit_2511_fp8mixed.safetensors` | `Comfy-Org/Qwen-Image-Edit` | 19.6 GB |
| `qwen_image_edit_2511_int8_convrot.safetensors` | same | 19.5 GB |
| `qwen_image_edit_2511_bf16.safetensors` | same | 39.0 GB |

82 s per ~1 MP edit on a 4090 at fp8, 40 s with the 8-step Lightning LoRA, 450 s without LoRA at 20 steps and CFG 4 †. On L4, fp8 fits with the encoder; on T4 use a GGUF Q4 build, expect minutes.

**FLUX.2 Klein 4B** (Apache 2.0) is the cheap, fast editor: 4B transformer 7.4 GB + 4B text encoder 7.7 GB + 0.3 GB VAE (15.4 GB of files), about 13 GB of VRAM per the vendor †, distilled variant "about one second" per image on a 4090 †. ComfyUI has a native template. This is the best T4 editing model.

## Video

### With sound

**MiniMax H3** (33B, 20B pruned) is already measured here: 10.1 s at 1280×736 with stereo audio in 344 s on A100 40 GB, 0.64 units, 8-step turbo LoRA (`recipes/minimax-h3/`). Files: 20.0 GB int8 transformer, 15.7 GB NVFP4 text encoder, plus VAEs and LoRA. Licence: MiniMax H3 Community, **excludes the US, EU, UK and South Korea**, and written approval above $20M revenue.

**LTX-2.5** (22B + Gemma 4 12B encoder) is the alternative with native audio, multishot and 4K HDR. Vendor floor is 32 GB VRAM, but the int8 ComfyUI files run on a 16 GB card at 15.8 GB VRAM with 45 GB system RAM: 75 s for a 2 s 480×832 clip, 88.3 s for 5 s at 480×832 †. Files: int8 transformer 20.5 GB, int8 encoder 14.7 GB, video and audio VAEs, latent upscaler. Licence: LTX-2.x Community, **free under $10M annual revenue**, no competing product. ComfyUI ships four native workflows.

**Kandinsky 6.0 Lite** (3B, MIT, 44 kHz audio with lip-sync) is the only permissively licensed sound model that fits every tier. Lite distill 5 s clip: 68 s on 4090, 173.7 s on a 16 GB RTX 5060 Ti, 78.6 s on A100 80 GB †. Files: 6.4 GB transformer in the distill Diffusers repo, ~27 GB total; int8 ConvRot community builds exist. ComfyUI support is a registry node (`kandinsky6`), not a core template.

Estimates: LTX-2.5 5 s at 480×832 with audio — A100 0.11 u, L4 0.075 u, T4 0.14 u (the last two only if the VM has ≥45 GB RAM). Kandinsky Lite — A100 0.16 u, L4 0.11 u, T4 0.19 u.

### Without sound

**Wan 2.2 TI2V-5B** (Apache 2.0, no territory limits) is the workhorse: one 10.0 GB fp16 model, 6.7 GB fp8 text encoder, 1.4 GB VAE. Wan's own measurement: 534.7 s for 5 s 720p on a 4090, 22.9 GB peak †. ComfyUI's template runs it at 8 GB with offload; a 16 GB card did 2 s at 480×832 in 60 s and 2 s at 736×1280 in 114 s †. Estimates: 5 s 720p — A100 0.9 u, L4 0.54 u, T4 0.95 u.

**HunyuanVideo 1.5** (8.3B, 14 GB with offload) when you want the smallest good 480p/720p model: 75 s for a 480p clip on a 4090 with the step-distilled checkpoint †, 297 s for 5 s at 848×480 †. Licence: Tencent Hunyuan Community, **excludes EU, UK and South Korea**. ComfyUI support via Tencent's guide and a community plugin.

**Wan 2.2 A14B** (Apache 2.0) is the quality pick but awkward here: 35.6 GB of fp8 files, 41.3 GB peak at 480p and 59.8 GB at 720p in Wan's own test †, so 720p is out on 40 GB and 480p needs offload. A 24 GB 4090D ran 640×640 in 536 s, or 108 s with the 4-step LoRA †. On A100, 480p should land near Wan's own 785.7 s measurement, about 1.5 units per 5 s clip.

## Upscaling

**SeedVR2** (ByteDance, 3B and 7B, Apache 2.0) is the one-step diffusion restorer for images and video, native in ComfyUI since 0.28 with templates for both.

| File | Repo | Size † |
| --- | --- | --- |
| `seedvr2_3b_int8_convrot.safetensors` | `Comfy-Org/SeedVR2` | 3.3 GB |
| `seedvr2_3b_fp16.safetensors` | same | 6.5 GB |
| `seedvr2_7b_int8_convrot.safetensors` | same | 7.9 GB |
| `seedvr2_7b_fp16.safetensors` | same | 15.7 GB |

Measured: 7B fp8 took 451 frames of 640×480 to 1440×1080 in 9.0 min at 0.83 fps, 15.2 GB peak on a 4090 †. 3B int8 ran at 0.24 fps with 11.4 GB peak in a separate test †. VAE tiling is mandatory; without it decode was 17x slower after spilling to RAM †. Estimates per 10 s 24 fps clip (240 frames): A100 0.45 u, L4 0.29 u, T4 0.46 u.

**Real-ESRGAN** (BSD-3) is the cheap fallback for a 2x/4x pass where no restoration is needed; it adds no detail. ComfyUI has built-in upscale nodes.

## Music and songs

> **Dropped (2026-11-24):** after testing ACE-Step 1.5 turbo and XL against Suno, the owner chose Suno
> for songs; see `docs/music-generation.md`. Everything below in this section is historical research from
> before that test, not a recommendation.

**ACE-Step 1.5** (2B turbo / 4B XL, MIT) looked like the pick before testing: full songs with vocals, 10 s to 10 min, 50+ languages, under 4 GB VRAM for the 2B turbo and 12-20 GB for XL, "under 2 s per full song on an A100 and under 10 s on an RTX 3090" †. ComfyUI has an AIO checkpoint template.

| File | Repo | Size † |
| --- | --- | --- |
| `ace_step_1.5_turbo_aio.safetensors` | `Comfy-Org/ACE-Step-1.5` | 9.6 GB |
| `acestep_v1.5_xl_turbo_bf16.safetensors` | same | 9.5 GB |
| `qwen_1.7b_ace15.safetensors` (encoder) | same | 3.5 GB |

Estimates: 0.005 u per song on A100, 0.008 on T4 — the cheapest useful output in this document.

**MiniMax Music 3** (11.1B, up to 5 min, 32 kHz) when ACE-Step's vocals are not good enough. 24 GB in bf16, so L4/A100; ComfyUI template exists. Licence: MiniMax-Music3 Community, attribution required, written approval above $20M revenue. ComfyUI's pruned int8 files total about 14 GB: DiT 4.7 GB fp16, text encoder 8.8 GB int8, VAE 0.2 GB.

**YuE2** scores best on its own benchmark but the weights are **CC BY-NC 4.0** (companies need a licence) and it needs 24 GB. **HeartMuLa** (3.9B, Apache 2.0, ~22 GB) is the permissive alternative. **MOSS-SoundEffect v2.0** (1.3B, Apache 2.0) covers sound effects up to 30 s.

## Speech to text

**Qwen3-ASR 1.7B** (Apache 2.0) is the accuracy pick: 5.40% average WER, 819 RTFx on the Open ASR Leaderboard, 30 languages plus 22 Chinese dialects, singing, language ID. 4.5 GB in bf16, 4.3 GB peak VRAM †. Qwen's own report: RTF 0.0148 at concurrency 1 (~68x real time), throughput up to ~1,000x at high concurrency on a datacentre GPU †.

**Whisper large-v3-turbo** (MIT, 99 languages) is the compatibility pick: 1.7 GB at int8, 80x real time single-stream on a 4090, 175x batched at 16 †. Runs everywhere, including CPU.

**Parakeet TDT 0.6B v3** (CC BY 4.0, 25 European languages) is the throughput pick, 6,132 RTFx on an H200 †, but needs NeMo, not vLLM.

Estimates per audio hour: A100 0.10 u (Qwen3-ASR), L4 0.05 u, T4 0.07 u (Whisper turbo int8 or Qwen3-ASR 0.6B). Use `Qwen3-ForcedAligner-0.6B` when you need timestamps. ComfyUI has no ASR node for these; run them as batch scripts, or use its Gemma 4 template for one-off transcription.

## Text to speech and voice

**Qwen3-TTS** (0.6B/1.7B, Apache 2.0) is the pick: 10 languages, cloning from ~3 s of audio, streaming at ~97 ms latency, voice design variant. 1.7B Base is 3.7 GB + 0.65 GB speech tokenizer, ~4.6 GB peak VRAM †.

Measured RTF for 1.7B: 0.45 on T4, 0.44 on an RTX 4060 with int4/int8, 0.55 on A100 (kernel-latency bound, not bandwidth) †. So one audio hour takes ~27 min on T4 (0.65 u), ~15 min on L4 (0.45 u), ~33 min on A100 (3.7 u). Batch on L4, not A100.

Alternatives: **Kokoro-82M** (Apache 2.0, 54 fixed voices, 8 languages, runs on CPU, no cloning) for narration; **VoxCPM2** (2B, Apache 2.0, 30 languages, 48 kHz, ~8 GB) for quality cloning; **Chatterbox** is MIT but was retired in August 2026 — do not build on it. **VibeVoice** is MIT on the card but marked research-only; **OmniVoice**, **Fish Audio S2 Pro**, **Breeze TTS 2** and **Higgs TTS 3** are non-commercial or revenue-capped.

There is no core ComfyUI template for Qwen3-TTS; use the Python API or the community `ComfyUI-Qwen3-TTS-Triton` node. ComfyUI's native audio templates are for music (ACE-Step, YuE2, MiniMax Music 3), not TTS.

Voice cloning: only consenting voices, per the repo's Colab policy on deepfakes.

## Image and video to 3D

**TRELLIS.2** (4B, MIT) is the pick: single image to PBR-textured mesh up to 1536³, native in ComfyUI core with a template shared with Pixal3D.

| File | Repo | Size † |
| --- | --- | --- |
| `trellis_2_int8_convrot.safetensors` | `Comfy-Org/TRELLIS.2` | 5.0 GB |
| `trellis_2_bf16.safetensors` | same | 9.9 GB |
| `dino_v3_vit_l.safetensors` | same | 1.2 GB |
| shape + texture VAEs | same | 2.0 GB |

Measured: 232.6 s per asset on a 16 GB RTX 5060 Ti with int8, 13.95 GB peak †; 17 s at 1024³ and 60 s at 1536³ on H100 †. Estimates: A100 0.22 u, L4 0.12 u, T4 0.22 u per asset.

**Pixal3D** (Tencent ARC, MIT) shares the workflow and is faster (185.6 s on the same 16 GB card, 15.6 GB peak †). **Hunyuan3D 2.1** (Tencent licence) is faster still (96 s †) but ComfyUI core support is shape-only, with no texture.

Video to 3D: there is no strong open model that runs here. TRELLIS.2 and Pixal3D take a single image; for video, extract keyframes and run them separately.

## LLM batch work

| Tier | Model | File | Notes |
| --- | --- | --- | --- |
| A100 40 GB | **Qwen3.5-27B** (Apache 2.0) | `cyankiwi/Qwen3.5-27B-AWQ-4bit`, 18.8 GB loaded † | 62 tok/s single stream, 6.4 ms/token with MTP † |
| A100 40 GB | Qwen3.6-35B-A3B (Apache 2.0) | Q4_K_XL GGUF 20.8 GB † | MoE, ~3B active; high throughput for batch |
| L4 24 GB | **Qwen3.6-35B-A3B** | Q4_K_XL 20.8 GB, or Q3_K for headroom | 1,081 tok/s aggregate at 64 concurrent with a 7B AWQ † shows the shape |
| L4 24 GB | Qwen3.5-9B (Apache 2.0) | bf16, ~18 GB | Safer fit, 175 tok/s at INT4 on A100 † |
| T4 16 GB | **Qwen3.5-4B** (Apache 2.0) | fp16 | T4 has no bf16; 68 tok/s for a 1.5B fp16 model † is the realistic order |
| T4 16 GB | gpt-oss-20b (Apache 2.0) | MXFP4 13.1 GB † | Fits, tight; llama.cpp rather than vLLM |

Avoid gpt-oss-120b (63 GB at MXFP4) and GLM-4.6 (355B) on these tiers. For batch jobs, vLLM on A100/L4 and llama.cpp on T4 is the simplest split. ComfyUI has a `TextGenerate` node with templates for Gemma 4 and Qwen3.5 if you want captioning or prompt rewriting inside a workflow, but batch throughput is better from vLLM.

## Fine-tuning

**LLMs — Unsloth QLoRA.** Published minimums †: 8B 6 GB, 14B 8.5 GB, 27B 22 GB, 32B 26 GB. So T4 handles up to 8B, L4 up to 14B comfortably (27B is tight), A100 up to 32B. T4 has no bf16, so use fp16 QLoRA and expect roughly half the speed of L4 per step.

**Image LoRAs.** Z-Image is the cheap one: OneTrainer ships an 8 GB preset (512px, fp8 transformer, layer offload 0.6) †, SimpleTuner says 10-12 GB for a rank-16 NF4 LoRA †. Qwen-Image needs 12 GB with musubi-tuner (`--fp8_base --fp8_scaled --blocks_to_swap 45`) or 24 GB with diffusion-pipe/ai-toolkit †. Qwen-Image-Edit-2511 needs 24 GB †. So: Z-Image LoRA on every tier, Qwen-Image LoRA on L4/A100, Qwen-Edit LoRA on A100.

**Video LoRAs.** Wan 2.2 A14B: 24 GB with musubi-tuner or ai-toolkit, 16 GB for I2V with SimpleTuner †. MiniMax H3, LTX-2.3 and Wan 2.2 are all supported by musubi-tuner and diffusion-pipe. A100 is the sane tier for video training; L4 works for short, low-resolution clips.

**Music LoRAs** (historical; music is dropped, see `docs/music-generation.md`). ACE-Step 1.5 trains a style LoRA from a few songs †.

**Not practical here:** full fine-tunes (Wan A14B needs multi-GPU FSDP; LTX-2.5 full fine-tune is 4-8 H100s), and FLUX.2 dev training (non-commercial licence plus 32B).

## Next five recipes

Cheapest and most useful first. Each should follow `recipes/minimax-h3/`: `models.txt` for aria2, `remote.sh`, a ComfyUI API workflow JSON, and a README with measured times and units.

1. **`z-image` — images on L4.** Z-Image Turbo bf16 + Qwen3-4B encoder + VAE, 20 GB download, 21 GB peak. Expect ~12 s and ~0.006 units per 1024² image. Also add FLUX.2 Klein 4B as the edit/T4 variant in the same recipe. Highest output per unit of anything here, Apache 2.0, core ComfyUI template.
2. **`ace-step` — songs on T4 or L4.** One 9.6 GB AIO checkpoint, under 4 GB VRAM, seconds per song, MIT. Proves the audio path end to end with almost no setup cost.
3. **`speech` — batch transcription and TTS on T4.** Qwen3-ASR 1.7B (4.5 GB) and Qwen3-TTS 1.7B (4.4 GB) in one script, no web UI. Gives the studio a subtitle/voiceover path and is the cheapest way to use a T4.
4. **`upscale` — SeedVR2 3B on L4.** 3.3 GB int8 model plus template; finishes H3's 1280×736 clips to 1080p. ~0.29 units per 10 s clip. Reuses existing outputs, so it is useful immediately.
5. **`wan-5b` — silent video on L4.** Wan 2.2 TI2V-5B fp16, 18 GB of files, 8 GB with offload, Apache 2.0 with no territory limits. ~0.54 units per 5 s 720p clip, cheaper than H3 on A100 and usable for B-roll and image-to-video. This is the fallback when H3's licence or the A100 queue blocks a job.

Close sixth: **`trellis-3d`** (TRELLIS.2 int8, 8 GB of files, 0.12 units per asset on L4) — cheap and fun, but less often needed than the five above.

## Sources

Checked 2026-11-23 unless the source is dated.

- GPU rates and H3 measurement: this repo, `recipes/minimax-h3/README.md`, `config/account.env`.
- Image models, licences and VRAM: [Quantacloud image model guide](https://quantacloud.net/guides/open-source-image-generation-models), [Windpaint](https://windpaint.ai/blog/best-open-source-image-models), [VDF AI](https://vdf.ai/blog/best-local-image-generation-models/), [Murasame](https://murasame-atelier.com/en/local-image-generation).
- Z-Image speed: [ParalonCloud 4090 benchmark](https://paraloncloud.com/resources/z-image-turbo-cloud-gpu), [ComfyUI vs Forge on 16 GB](https://efraingaray.com/en/blog/comfyui-vs-forge-16gb/).
- Qwen-Image-2512 speed: [CSDN 4090 comparison](https://blog.csdn.net/qq_42590163/article/details/162270655), [byteshape](https://byteshape.com/blogs/Qwen-Image-2512).
- Qwen-Image-Edit-2511 speed: [ComfyUI test on 4090](https://note.com/kongo_jun/n/n3f469bfe78a7).
- Video VRAM and speed: [LTX VRAM guide](https://ltx.io/blog/open-video-model-vram-requirements), [Quantacloud Wan 2.2 guide](https://quantacloud.net/guides/wan-2-2-video-comfyui), [Home AI Bench 16 GB comparison](https://homeaibench.com/notes/2026-11-18-four-video-models-16gb/), [ComputingForGeeks Wan 2.2](https://computingforgeeks.com/run-wan-video-generation-locally), [HunyuanVideo 1.5 GitHub](https://github.com/Tencent-Hunyuan/HunyuanVideo-1.5), [HunyuanVideo discussion timings](https://huggingface.co/tencent/HunyuanVideo-1.5/discussions/3), [smeltcore 480p distilled](https://smeltcore.com/recipes/hunyuanvideo-1-5-on-rtx-4090-480p-step-distilled-text-to-video-in-75-seconds).
- Kandinsky 6.0: [kandinskylab/kandinsky-6](https://github.com/kandinskylab/kandinsky-6) (performance table, MIT), [InferenceKey](https://inferencekey.com/news/kandinsky-6-video-audio-open).
- Licences: [LTX-2.x licence](https://github.com/Lightricks/LTX-2/blob/main/LICENSE-2_x), [LTX licensing FAQ](https://ltx.io/model/license), [HunyuanVideo 1.5 licence](https://github.com/Tencent-Hunyuan/HunyuanVideo-1.5/blob/main/LICENSE), [Imaginode licence table](https://imaginode.ai/en/blog/best-open-source-ai-video-models).
- Upscaling: [ComfyUI SeedVR2 docs](https://docs.comfy.org/tutorials/utility/seedvr2), [Quantacloud SeedVR2](https://quantacloud.net/guides/seedvr2-video-upscaling), [Pixedi 4090 measurement](https://pixedi.com/lab/seedvr2-vs-esrgan-4090), [SeedVR2 INT8 PR](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler/pull/624).
- Music: [ACE-Step 1.5 GitHub](https://github.com/ace-step/ACE-Step-1.5), [ComfyUI ACE-Step 1.5 docs](https://docs.comfy.org/tutorials/audio/ace-step/ace-step-v1-5), [ai-opensource music guide](https://ai-opensource.com/guides/how-to-choose-a-music-generation-model/), [YuE2](https://github.com/multimodal-art-projection/YuE).
- Speech to text: [Open ASR Leaderboard summary](https://pinggy.io/blog/best_open_source_self_hosted_speech_to_text_models/), [Qwen3-ASR technical report](https://arxiv.org/html/2601.21337), [Baseten batch transcription](https://www.baseten.co/blog/fastest-lowest-cost-qwen3-asr-batch-transcription/), [Whisper 4090 benchmark](https://gigagpu.com/rtx-4090-24gb-whisper-benchmark/).
- Text to speech: [Quantacloud TTS comparison](https://quantacloud.net/guides/open-source-tts-models), [VDF TTS](https://vdf.ai/blog/best-local-tts-models/), [Cartesia TTS licences](https://www.cartesia.ai/learn/open-source-tts), [faster-qwen3-tts benchmarks](https://github.com/andimarafioti/faster-qwen3-tts), [Qwen3-TTS CUDA performance](https://github.com/mkramer0820/qwen3-tts-C/blob/main/docs/cuda-performance.md).
- 3D: [TRELLIS.2 project page](https://microsoft.github.io/TRELLIS.2), [ComfyUI TRELLIS.2 docs](https://docs.comfy.org/tutorials/3d/trellis2), [16 GB comparison](https://note.com/humble_hornet125/n/nc553e4f74a9b), [ComfyUI 3D announcement](https://blog.comfy.org/p/trellis2-and-pixal3d-are-now-native).
- LLM serving: [A100 40 GB model table](https://apxml.com/hardware/nvidia-a100-40gb), [Qwen3.5-27B on A100](https://medium.com/@willyouzhizou/serving-a-capable-open-source-agent-model-on-gpus-you-can-actually-rent-qwen3-5-27b-63887455c92f), [L4 vLLM benchmark](https://github.com/Aman12x/vllm-serving-bench), [vLLM on Colab T4](https://github.com/ishwar6/ishwar-books/blob/main/content/writings/llm-inference-8-vllm-on-colab.md).
- Fine-tuning: [Unsloth requirements](https://unsloth.ai/docs/get-started/fine-tuning-for-beginners/unsloth-requirements), [LoRA VRAM by model and trainer](https://vramready.com/lora-training), [musubi-tuner](https://github.com/kohya-ss/musubi-tuner), [diffusion-pipe](https://github.com/tdrussell/diffusion-pipe).
- ComfyUI templates: [tutorial index](https://docs.comfy.org/_llms/en/tutorials.txt).
- Hugging Face repos, file sizes and gated status: Hugging Face API, 2026-11-23.
