# Song generation: ACE-Step 1.5 vs Suno vs ElevenLabs

What we learned on 2026-11-24 when we gave two existing songs to three generators. We gave each one the
lyrics and the written style brief only, never the original audio. The songs were "Just as Sure"
(intimate indie alt-pop, 100 BPM, female vocal) and "The Arrow" (dark acoustic ballad, 92 BPM, baritone,
no percussion until the final chorus). Suno made the originals.

## Short version

- **Suno** is still the reference for production quality and for following a detailed style brief.
- **ElevenLabs** sang every lyric. In a first-pass listen it rated about 6/10. That test used the
  *oldest* model (`music_v1`) with no audio reference and no finetune, so it is a floor, not a verdict.
  Re-test on `music_v2_5` before deciding (see "ElevenLabs: what we did not use yet").
- **ACE-Step 1.5 turbo** (open weights, runs on a free-tier-class T4) gave exact length, BPM and key with
  clear vocals. It was weak at following a production brief, and lyric completeness depended on the seed.
  It is the only option that can be fine-tuned on your own audio without a vendor's rules.

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

Not tried yet ("round 2", planned for an A100): the larger ACE-Step model, more steps than turbo's 8, the
LM planner for structure, and repaint/edit of single sections. A LoRA on your own recordings is possible
in principle, but only with audio you own (see Terms).

## ElevenLabs Music

How we called it: the `POST /v1/music` API with a `composition_plan` built from the lyrics. There was one
section per `[Section]` tag, the lines and their cue went in as local styles, and the brief went in as
global styles. Section lengths were weighted by line count, then scaled to the original song's length.
Output was MP3 at 44.1 kHz, 128 kbps, the Starter plan's maximum.

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
| Custom Finetunes | Train on up to 50 of your own tracks (10 s to 10 min each, at most 250 min total), ready in 5-10 min | App only; API is Enterprise on request (`finetune_id` exists in the API) | Shapes sound, not structure. Uploads are screened, and a rejected finetune is not refunded |

There is no "voice type" finetune separate from music finetunes. A custom finetune learns a vocal style
only if the uploaded tracks contain vocals. The Music docs we read offer no way to pick a cloned speech
voice (the kind used for voiceovers) as the singer. Describe the singer in the prompt or styles instead.

The plan tiers that can create *custom* finetunes are not stated on the docs pages we read. Check the
Finetunes page in the app before relying on Starter or Creator.

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

## Next test, if ElevenLabs is the candidate

1. Rebuild the two plans in the v2.5 chunk format. Put the instrumentation in each chunk's positive styles
   and the forbidden elements in its negative styles.
2. Generate both songs on `music_v2_5` with two seeds each, at the same lengths.
3. In the app, add an Audio Reference that we own (a self-made 30 s sketch, not the Suno track), and try
   "Golden Hour Indie Guitar" on The Arrow.
4. Inpaint only the weakest section of the best take instead of re-rolling.
5. Compare against Suno in the same `songs-compare` format (one MP4 per take with a waveform).
