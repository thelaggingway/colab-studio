# Making short ads with video models

What two 18–20 s parody ads taught us on 2026-11-24: **Storm Surge** (a live-action energy drink ad,
MiniMax H3 and LTX-2.5) and **GATOR-NOPE** (a 1950s cartoon alligator repellent ad, LTX-2.5 with H3 fixes).
Version 1 was out of sync, had pop-ins, and its story didn't hold together. Version 2, re-shot and re-cut
with the rules below, fixed most of that for about 5.35 units of A100 time.

## The core idea: the edit owns the timing, not the model

Version 1 asked each model for a whole multi-shot ad in one clip. The models placed their own cuts 1 to 2 s
late, invented extra people mid-shot, and changed the product between shots. Version 2 inverted the job:

1. **Write and record the voiceover first, and never cut it.** It is the clock for everything else.
2. **Time every line,** with word timestamps (for example faster-whisper) or silence detection.
3. **Plan one shot per line or pair of lines,** with the cut 0.1–0.15 s before the line starts.
4. **Generate each shot as its own clip,** one continuous shot with no cuts, a little longer than needed.
5. **Cut and mix in ffmpeg,** where cuts are frame-exact (`scripts/assemble-ad.sh`).

A model is good at one shot with one or two timed actions. It is bad at a storyboard.

## Rules for prompts and clips

- **One continuous shot per prompt.** Write "One continuous shot, no cuts." LTX-2.5 dissolves between
  storyboard shots, and H3's own cuts land late.
- **Put everything in the first frame.** Pop-ins came from prompts where people and props "join" during the
  shot. Say "everyone is in frame from the first frame", or lock the first frame (below).
- **Time actions in seconds** ("lightning at 0.5s", "sprays from 1.7s to 2.7s"). H3 follows these well.
  Three or more actions in one shot is where LTX skips one.
- **Every constraint goes in the main prompt.** The LTX recipe runs at CFG 1.0, so its negative prompt does
  nothing. "No text, subtitles, logos or watermarks" goes at the end of every prompt.
- **Describe the sound too.** Both models make native audio. Name the effects and their timing (thunder on
  the flash, spray hiss) so the bed under the voiceover already matches the picture.
- **Two seeds per clip,** then pick. One of two seeds was often clearly worse.

## Locking frames: the fix for products and continuity

Video models paint a fake brand on any drink can ("Euelis", "Corlnt") however hard the prompt forbids it.
What worked:

- **Make a still of the shot with the painter tool** ("keep everything identical, change only: the can's
  label is plain lime green with no letters"), check it for letters, then turn it into a one-frame video.
- **Hand it to H3 as the first frame, and also the last frame for a static product shot**
  (`recipes/draft-handoff/handoff.py --draft first.mp4 --last still.png`). The blank label held in both
  takes.
- **Leave the product blank in the generated video.** The brand lives in the end card, or in a flat label
  laid over a locked-off shot in post.
- **Pre-placed first frames removed the pop-ins** in the float-by shot.

What didn't work yet: **character continuity.** Only the shots that got a still were locked, so each ad
still has three or four different men in similar shirts. The fix is the same technique applied to every
shot: make one reference image of the hero, derive each shot's first frame from it with painter, and hand
each to H3.

## Which model for which shot

| Need | Use | Why |
| --- | --- | --- |
| A style (1950s cartoon), cheap drafts, rain and weather | LTX-2.5 | Nailed the cartoon look in every take; about 0.1 units per 10 s clip |
| Timed actions, a reaction, synced sound | H3 | Follows "at 2.5s" timings; sound lands on the action |
| A locked product or a set first frame | H3 with `draft-handoff` | First and last frame conditioning |
| An LTX draft that skipped an action | H3 from the draft's first frame | Keeps the look, adds the action (GA2 and GA3 in GATOR-NOPE) |

Practical details:

- **Length snaps to a grid.** H3 `--seconds 5` gives 5.17 s, `--seconds 6` gives 6.58 s; LTX takes whole
  seconds.
- **Sizes differ:** LTX makes 1280×704, H3 1280×736. The assembly script crops everything to 1280×704.
- **Glitches sit at clip starts.** One LTX product shot had scribble-like tearing in its first 1.25 s.
  Find the clean point on a dense frame sheet (8–12 fps) and start the segment after it.

## Mix and end card

Measured problems in v1: the voice sat 0–3 dB under the music, one ad's music died halfway, and the end cards
popped on over a cut. What `scripts/assemble-ad.sh` does now:

- **One uncut voiceover,** delayed 0.2–0.3 s so the first line clears the opening frame.
- **The clips' own sound as the bed,** at 0.55, ducked under the voice with
  `sidechaincompress=threshold=0.02:ratio=8:attack=20:release=400`. Each segment's audio fades over 40–50 ms
  so cuts don't click. The bed fades out over the last 1.2 s instead of stopping dead.
- **`VO_BOOST` for one masked line.** A thunder crack buried "Not a flotation device"; doubling the voice
  from 15.3 to 19.6 s fixed it.
- **Loudness `-16 LUFS, -1.5 dBTP`** for both ads. Measured: −16.6 and −16.7 LUFS, peaks −1.6 dBFS.
- **End card as a transparent PNG** that fades in over 0.3 s on a line, over live picture, with no cut or
  freeze under it. Keep it off faces and off the payoff: GATOR-NOPE's band moved to the bottom.
- A short segment's last frame is held (`tpad`) rather than leaving a gap.

Voiceover: ElevenLabs `eleven_v4` with inline audio tags for the emotional turns, for example
`[deadpan, completely unbothered] Evacuation orders? [scoffs]` and
`[suddenly terrified, voice cracking, gulps] your... ARMS.` A turn the listener must notice needs a strong
contrast in the tags; a mild one comes out subtle.

## Reviewing a cut

What found the v1 problems, cheapest first:

- **Scene detection** (`ffmpeg ... select='gt(scene,0.3)'`) for where the cuts really are.
- **Word timestamps of the voiceover** against the cut list: does each line play over the thing it names?
- **Frame sheets** at 4–12 fps around each cut and each suspected pop-in. Contact sheets at 1 fps miss
  pop-ins.
- **EBU R128 loudness** of the whole ad and of the voice against the bed during each line.
- **Band-energy onsets** (below 160 Hz for thunder, above 5 kHz for hiss) to check sound against picture.

These are automated checks; a human still has to watch and listen before publishing.

## Running the session

- **Hold the GPU in a supervised service** (`amp orb service start studio-a100 --command '... studio-up.sh ...'`)
  and keep the holding thread's context small. The A100 was lost twice: once when its thread's orb
  paused, and once when the thread crashed on a request too large to send. Many contact-sheet images in one
  thread caused that. Colab reclaims the runtime about 20 minutes after its holder goes away.
- **Order:** LTX drafts first (its weights load fastest), make the painter stills while they run, then
  switch to H3 for the locked and timed shots.
- **Measured on the A100:** LTX 30–80 s per clip (0.06–0.15 units); H3 127–199 s per 5–6.6 s clip
  (0.24–0.37 units), plus about 2 minutes for the first load. 20 clips, both ads: about 5.35 units.

## The two ads, as built

Each segment is `file|source start|length`; the voiceover runs over all of them.

**Storm Surge v2** (20.3 s): LTX suburb (2.2 s) → LTX man on the roof (2.2) → H3 blank hero can (3.35) →
LTX can crack (2.25) → LTX can raised in the flood (2.0) → H3 hero can (1.6) → H3 float-by, everyone in
place (2.95) → H3 sunrise with the end card (3.75). Voice gain 2.0, 0.3 s in, card at 16.55 s.

**GATOR-NOPE v2** (17.9 s): LTX grill and splash (2.7 s) → H3 alligator rises, jaws at the arm (5.15) →
H3 can up, one spray, alligator recoils (5.6) → LTX product shot from 1.45 s, with the end card (4.45).
Voice gain 1.2, 0.2 s in, card at 13.6 s.

Still open on both: different characters from shot to shot (fix above), Storm Surge's foam still morphs
at the crack, and GATOR-NOPE's alligator never winks in the product shot.
