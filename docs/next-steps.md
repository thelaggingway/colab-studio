# Status and next steps (handover)

Read this first when continuing Colab Studio in a new thread. The founding thread is
https://ampcode.com/threads/T-01a20790-6b8b-7709-9a3b-e71bb27b5c86 (use read_thread for detail); its
child threads did the L4/T4 test, the runbook, the model research and the prior-art search.

## State on 2026-11-24

- **The GPU holder exists.** The always-on server (`lucky-fox`, runner `agent-hostuplarge`) holds a
  Colab GPU as a systemd `--user` service, so it survives the agent thread, a logout and a reboot; a
  timer checks it every 5 minutes and alerts on a lost GPU, a dead holder, and spend over a cap.
  `scripts/gpu-status.sh` is the one-line status. Design, setup, failure modes and how an agent thread
  submits work: `docs/gpu-holder.md`.
- **Three GPUs were lost that day** because the holder lived inside an agent orb: one orb paused after
  an idle turn, and two crashed on `request body length limit exceeded` with contact sheets in context.
  Hence the rule in `AGENTS.md` rule 7: images only through `view_media` with an objective.
- Still owed: one short T4 end-to-end test of the holder (grab, setup, a job, watchdog release), and an
  alert channel (an ntfy topic in `~/.config/colab-studio/alerts.env` on the server; until then alerts
  only reach `~/.local/state/colab-studio/monitor.log`).
- **Ads v3 are done:** one locked hero per ad fixed the character changes; lessons and remaining nits in
  `docs/ad-production.md`. A100 session 12:59–14:20 UTC, 8.96 units for the ads and ACE round 2.
- **Music is dropped.** The owner chose Suno after ACE-Step (turbo and XL) and ElevenLabs (v1 and v2.5)
  all lost by ear; see the decision in `docs/music-generation.md`. Do not start music work without asking.

## State on 2026-11-23 (end of day, UTC)

- **Account:** Google AI Pro, 200 compute units/month. Balance 174.42 after all of today's work.
  Entitled: G4, A100 (40 GB SXM4), L4, T4, TPU v6e1/v5e1. Not entitled: H100.
- **No GPU running.** One unnamed CPU runtime (`m-s-use1c8-2a6m39iaqrrca`, ~0.08 units/h) appeared at
  16:58 UTC from an unknown command run without `-s`. `colab stop` needs a session name, so stop it
  from Colab's web UI (Runtime > Manage sessions) if it is still listed in `colab sessions`.
- **Login:** project secret `COLAB_OAUTH_TOKEN_B64` on Amp project `yashj/colab-studio`; `.agents/setup`
  restores it (confirmed in fresh orbs). It is the user's main Pro account; the user plans to revoke it
  later (myaccount.google.com > Security > Third-party connections). A new Amp project on this repo needs
  the same secret, plus `HF_TOKEN`, set on it.
- **Hugging Face:** `HF_TOKEN` (the owner's Hugging Face account, fine-grained, gated-repo read on). Licence accepted for
  `Lightricks/LTX-2.5`. Other gated repos need the same one-time acceptance in the browser.
- **Drive:** outputs save to `Colab Studio/outputs/<date>/<session>/` with `scripts/drive-save.sh`,
  billed to the owner's Cloud project (Drive API enabled), set as the Amp project env var
  `DRIVE_QUOTA_PROJECT` on `yashj/colab-studio`, not in the repo. Today's 13 clips, contact sheets
  and comparisons are in `Colab Studio/outputs/2026-11-23/h3`.
- **Merged on main:** runbook, hardened scripts, Drive saves, faster install (uv), H3 recipe with
  A100/L4/T4 numbers, LTX-2.5 recipe, model research (`docs/workflows.md`), prior art
  (`docs/prior-art.md`), and the draft -> H3 hand-off recipe.

## Measured so far

| What | GPU | Time | Units |
| --- | --- | --- | --- |
| H3 10 s 1280x736 (turbo) | A100 | 344 s | 0.64 |
| H3 10 s 1280x736 (turbo) | L4 | 19 min | 0.61 |
| H3 5 s 864x480 (turbo) | T4 high-mem | 32 min | 0.83 |
| LTX-2.5 10 s 1280x704 | A100 | 61 s warm / 106 s cold | 0.11 / 0.20 |
| H3 hand-off from an LTX frame, first + last frame | A100 | 352 s | 0.66 |
| Setup: 42-45 GB weights via aria2 | A100 | ~130 s | ~0.25 |

GPU availability: A100 and G4 often answer 503 (busy) for 10-30 minutes; G4 has never been obtained.
Two sessions (A100 + L4) can run at once.

## Remaining work, in order

| # | Task | Depends on | Notes |
| --- | --- | --- | --- |
| 1 | Hand-off retry with a last frame aligned to the first frame's framing | A100 or L4 | Should remove the push-in/pull-back; see `recipes/draft-handoff/README.md` |
| 2 | Measure the trimmed install on a real run | any GPU | `remote.sh` prints clone/apt/download/pip seconds; record them in the runbook |
| 3 | LTX-2.5 on L4 | L4 | L4 VM has 52 GB RAM, enough for the int8 files on paper; untested |
| 4 | `z-image` recipe (images) | L4 | Official template `image_z_image_turbo`; mostly assembly per `docs/prior-art.md` |
| 5 | ~~`ace-step` recipe (songs)~~ | dropped | Tested turbo and XL; the owner chose Suno. See `docs/music-generation.md` |
| 6 | `speech` recipe (ASR + TTS batch) | T4/L4 | `qwen-asr`, `qwen-tts`; never on A100 (rate) |
| 7 | `upscale` recipe (SeedVR2 to 1080p) | L4 | Finishes H3/LTX clips; step 5 of the hand-off workflow |
| 8 | `wan-5b` recipe | L4 | Apache 2.0 fallback with no territory limits |
| 9 | Chained 45 s video like the X post (4 shots, last frame -> next first frame, upscale) | A100 or G4 | Needs 1 and 7 |
| 10 | ~~Re-grab after an orb restart~~ | done | Solved by the holder: `scripts/gpu-holder.sh` runs under systemd on the server, adopts an existing session instead of re-grabbing, and the monitor restarts it when the GPU is lost. See `docs/gpu-holder.md` |
| 11 | Retry G4 at another time of day | G4 | Entitled; never assigned so far |
| 12 | After a plan change (for example Ultra) | user | Re-login (`scripts/login.sh`), update the secret, re-run `scripts/probe-gpus.sh`, update `config/account.env` |

## Working agreements from the founding thread

- Never wait for a GPU in the orchestrating conversation: run `studio-up.sh` as an orb service or
  delegate to a child thread or subagent that reports back on assignment and on completion.
- Hold an assigned GPU between jobs; the idle watchdog releases it (default 60 minutes). Report which
  sessions are running, and the balance, at the end of every turn that touched a GPU.
- Changes land through pull requests for the user to review; avoid stacked PRs (merging a stacked PR
  merges into the branch below, not main). Delete branches once their PR is merged and its commits are
  confirmed in main.
- Child threads: the user prefers `dsf41-neuralwatt` (or another dsf41 mode) on `a1.tiny` orbs.
- Share outputs as files in the thread and in Drive. ComfyUI through the Amp portal opens in a separate
  browser window and can look blank on a phone; use a laptop or direct `/view?filename=...` links.
