# Song generation: ACE-Step 1.5 vs Suno vs ElevenLabs (decision: Suno)

What we learned on 2026-11-24 when we gave two existing songs to three generators. We gave each one the
lyrics and the written style brief only, never the original audio. The songs were "Just as Sure"
(intimate indie alt-pop, 100 BPM, female vocal) and "The Arrow" (dark acoustic ballad, 92 BPM, baritone,
no percussion until the final chorus). Suno made the originals.

## Decision (2026-11-24): use Suno; music generation in this repo is dropped

After four rounds (ACE-Step turbo, ElevenLabs `music_v1`, ElevenLabs `music_v2_5`, full ACE-Step XL), the
owner judged **Suno clearly better on every song** and stopped the other experiments. Suno Pro is the
platform for songs. Nothing in this repo generates music any more; the notes below are kept so nobody
repeats the tests without a reason.

What did not move the verdict, so do not expect it to:

- **Metrics.** ACE-Step XL hit every lyric line, exact length and tempo, and the drum brief on one seed,
  and an automated listen rated ElevenLabs v2.5 about 9/10. The owner still heard both as worse than Suno,
  and ACE round 2 as *worse than round 1*. Tempo, lyric counts and model "listens" do not measure what
  makes a song good; only a human listen against the Suno take decides.
- **More model.** ACE-Step's full XL model at 50 steps with the 4B planner sounded worse to the owner than
  the 8-step turbo, despite better structure.
- **More control.** ElevenLabs' per-section styles fixed brief adherence but not the overall feel.

Reopen only if a new model release claims to beat Suno on vocals and production, and test it with one
song and one human listen before building anything.

## Short version (per generator)

- **Suno** is the reference for production quality and for following a detailed style brief.
- **ElevenLabs** sang every lyric. `music_v1` rated about 6/10; `music_v2_5` with per-section styles
  followed the brief (The Arrow kept drums out until the final chorus) but still lost to Suno by ear.
- **ACE-Step 1.5** (open weights) gave exact length, BPM and key with clear vocals. Turbo on a T4 was weak
  at following a production brief and lyric completeness depended on the seed; XL on an A100 fixed the
  lyrics but sounded worse. It is the only option that could be fine-tuned on your own audio.

## ACE-Step 1.5 on a Colab T4

Setup: ComfyUI 0.46.0, the all-in-one checkpoint `ace_step_1.5_turbo_aio.safetensors` (9.34 GiB, from
`Comfy-Org/ACE-Step-1.5`, `checkpoints/`), and ComfyUI's template `audio_ace_step_1_5_checkpoint.json`
rebuilt as an API graph. No Hugging Face token is needed. On a T4 (15 GB VRAM, 12.7 GB RAM), free any
other loaded model first (`POST /free`); RAM peaked at about 8.4 GiB.

Settings used for all four takes (only the seed changed, 42 and 7):

| Node | Settings |
| --- | --- |
| ModelSamplingAuraFlow | shift 3 |
| KSampler | 8 steps, cfg 1.0, euler, simple, denoise 1.0 |
| TextEncodeAceStepAudio1.5 | generate_audio_codes on, cfg_scale 2.0, temperature 0.85, top_p 0.9, top_k 0, min_p 0, time signature 4, language en, keyscale per song, duration and BPM per song |

Measured:

| Take | Length | Time on T4 | Tempo (librosa) | Notes |
| --- | --- | --- | --- | --- |
| Just as Sure s42 | 177 s | 180 s (incl. first load) | 99.4 (target 100) | All sections in order; first couplet garbled; arrangement close to the brief |
| Just as Sure s7 | 177 s | 171 s | 99.4 | Same family, drier and more intimate vocal; subtler chorus lift |
| The Arrow s42 | 213 s | 207 s | 92.3 (target 92) | Most lyric-faithful take; but synth-led with drums from verse 1, ignoring the acoustic brief |
| The Arrow s7 | 213 s | 198 s | 92.3 | Broken: 65 s intro, most of verse 1 missing, trap hi-hats, audible limiting |

Lessons:

- Duration, BPM and key are reliable controls. Use them to fit a song to a fixed time slot.
- Negative instructions buried in a long style paragraph ("no drums until the last chorus") are ignored.
  Put the instrumentation first and keep the caption short.
- Generate at least two seeds and listen for missing verses before you pick one.
- Peaks can reach 0 dBFS; normalise (for example to -14 LUFS, -1 dBTP) before publishing.

## ACE-Step 1.5 XL on an A100 ("round 2")

Setup: ComfyUI, the full (non-turbo) XL base in bf16, the 4B Qwen LM planner on (`generate_audio_codes`),
50 steps, cfg 6, exact duration/BPM/key, the caption = the style text with instrumentation moved first and
trimmed, lyrics verbatim. Two seeds a song. Weights about 20 GB, pulled on the VM.

| Take | Length | Tempo (target) | Lyric lines heard | True peak | Time |
| --- | --- | --- | --- | --- | --- |
| Just as Sure 4101 | 177.0 s | 99.4 (100) | 57/57 | +1.3 dBFS | 101 s (incl. load) |
| Just as Sure 4102 | 177.0 s | 99.4 | 57/57 | +0.9 | 34 s |
| The Arrow 4101 | 213.0 s | 92.3 (92) | 61/61 | +1.2 | 43 s |
| The Arrow 4102 | 213.0 s | 92.3 | 61/61 | +1.0 | 43 s |

- Lyrics complete on every take (faster-whisper small.en, word overlap per line); round 1's garbled
  couplet was gone.
- The Arrow 4102 kept percussion out until the final chorus (enters 2:38); 4101 had a muted kick under
  choruses 1 and 2. Judged by an audio-description model plus band-energy onsets, not by ear.
- Every take clipped (+0.9 to +1.3 dBFS true peak, about −11.5 LUFS).
- Tempo detection needs a prior near the target: librosa's default read one take as 136 BPM.
- No repaint: ComfyUI's 1.5 graphs have no section-edit node; the official pipeline has one but needs its
  own install.
- Cost: 1.66 units including the weight pull; generation itself was 0.06–0.19 units a take.
- **Owner's verdict: worse than round 1, and far from Suno.** This ended the ACE-Step experiments.

## ElevenLabs Music

How we called it: the `POST /v1/music` API with a `composition_plan` built from the lyrics. There was one
section per `[Section]` tag, the lines and their cue went in as local styles, and the brief went in as
global styles. Section lengths were weighted by line count, then scaled to the original song's length.
Output was MP3 at 44.1 kHz, 128 kbps, the Starter plan's maximum.

Re-test on `music_v2_5` (2026-11-24): both songs, two seeds each, plans rebuilt as v2.5 `chunks` with the
instrumentation in each chunk's positive styles and the forbidden elements (for example percussion in The
Arrow's verses) in its negative styles. Four takes cost 9,748 credits; the Starter plan allows only two
requests at a time. The Arrow kept drums out until the final chorus and an automated listen rated the
takes about 9/10, but the owner still preferred Suno, and the ElevenLabs music tests stopped there.
Audio Reference and finetunes were never tried (a finetune needs a higher plan than Starter).

### ElevenLabs: what we did not use yet

That plan format (`positive_global_styles` + `sections`) works only with `music_v1`, the oldest model. The
current options, from ElevenLabs' docs as of 2026-11-24:

| Control | What it does | Where | Notes |
| --- | --- | --- | --- |
| `model_id: music_v2_5` | Newest model: better audio and prompt adherence than v2 (v2 is the app's default) | API and app | v2/v2.5 plans are a list of `chunks`, not `sections`; section durations are always enforced |
| Audio Reference | Upload about 30 s of audio to guide sound, production style, instrumentation, tempo and mood | App (Music > Generations > + Reference); v2/v2.5, all paid plans | Copyright-screened. Guides style; does not transform genre |
| Inpainting | Keep parts of a stored song and regenerate others, such as one chorus or the outro; extend or loop | API: `store_for_inpainting`, then `song_id` + range chunks; v2/v2.5 | Fixes a weak section without re-rolling the whole song |
| Per-chunk styles | `positive_styles`, `negative_styles` and `context_adherence` on each generation chunk | API, v2/v2.5 | Use negatives per section ("percussion" in verse 1 of The Arrow) |
| `seed` | Repeatable takes (not guaranteed across updates) | API, plan-based calls only | |
| Curated Finetunes | 11 pre-trained styles, for example Golden Hour Indie Guitar, 80s Nu-Disco Revival, Mozart-Style Symphony | App | None matches these two songs closely; "Golden Hour Indie Guitar" is the nearest for The Arrow |
| Custom Finetunes | Train on up to 50 of your own tracks (10 s to 10 min each, at most 250 min total), ready in 5-10 min | App (Music > Finetunes) and API: `POST /v1/music/finetunes` to create, `GET /v1/music/finetunes` to list, then `finetune_id` on any compose call | Shapes sound, not structure. Uploads are screened, and a rejected finetune is not refunded. Each finetune is private to its creator unless shared to the workspace |

There is no "voice type" finetune separate from music finetunes. A custom finetune learns a vocal style
only if the uploaded tracks contain vocals. The Music docs we read offer no way to pick a cloned speech
voice (the kind used for voiceovers) as the singer. Describe the singer in the prompt or styles instead.

Which plans can create custom finetunes, and how many, is not settled by the sources we found
(2026-11-24). ElevenLabs' launch post (March 2026) says "Available to Creator+ subscribers". A third-party
guide from November 2026 says the pricing table lists them from Starter, and that the API charges $1.50 per
finetune. Neither the docs nor the pricing page we read gives a per-plan count. Check the Finetunes page in
the app, or `GET /v1/music/finetunes`, before paying for an upgrade for this.

What can go into a custom finetune: only audio you fully own that carries no third-party copyright. Suno
output is ruled out twice. Suno's terms forbid using its output to train other models, and ElevenLabs'
Prohibited Use Policy §12 forbids using output to train or fine-tune any model. Your own recordings or
original stems are fine.

## Terms (summary)

The full research, with quotes and dates, is in the thread's terms artifact. In short:

- **Suno Pro** ($10/month): commercial use, including monetised YouTube, for songs downloaded on the paid
  plan, within 20 downloads a month. Using its output to train other AI is forbidden.
- **ElevenLabs Creator** ($22/month): commercial use except film, TV, radio and games made with Studio.
  About 121k credits ≈ an hour of music. Prompts must not name real artists, songs or labels. Using its
  output to train or fine-tune is forbidden.
- **ACE-Step**: open weights; check the model licence for the checkpoint you use.

Neither service's audio can train a LoRA or a finetune. Train only on recordings you own.

## Not pursued

Steps 1–2 of the old ElevenLabs plan (v2.5 chunks, two seeds a song) were run, above. The rest (an
owned Audio Reference, a curated or custom finetune, inpainting the weakest section) were dropped with
the decision to stay on Suno. ElevenLabs is still used for voiceovers (TTS), which is a separate product.
