#!/usr/bin/env bash
# Assemble an ad from "file|src_start|length" segments: one uncut voiceover over the cuts, the clips' own
# sound ducked under it, a fading end card, loudness at -16 LUFS. See docs/ad-production.md.
# Usage: assemble-ad.sh <out.mp4> <vo.mp3> <vo_delay_s> <vo_gain> <card.png> <card_start_s> seg...
# Optional: VO_BOOST="'if(between(t,15.3,19.6),2.0,1)'" raises the voice in one window.
set -euo pipefail
out=$1 vo=$2 vd=$3 vg=$4 card=$5 cs=$6; shift 6
inputs=(); fc=""; i=0; cat=""
for seg in "$@"; do
  IFS='|' read -r f ss len <<<"$seg"
  inputs+=(-ss "$ss" -t "$len" -i "$f")
  fo=$(awk "BEGIN{print $len-0.05}")
  fc+="[$i:v]scale=1280:-2,crop=1280:704,setsar=1,fps=24,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=2,trim=duration=$len[v$i];"
  fc+="[$i:a]aresample=48000,aformat=channel_layouts=stereo,asetpts=PTS-STARTPTS,apad,atrim=0:$len,afade=t=in:d=0.04,afade=t=out:st=$fo:d=0.05[a$i];"
  cat+="[v$i][a$i]"; i=$((i+1))
done
n=$i
total=$(awk -v s="$*" 'BEGIN{n=split(s,a," ");t=0;for(k=1;k<=n;k++){split(a[k],b,"|");t+=b[3]};print t}')
fe=$(awk "BEGIN{print $total-1.2}")
vd_ms=$(awk "BEGIN{print int($vd*1000)}")
fc+="${cat}concat=n=$n:v=1:a=1[vc][bed0];"
fc+="[$((n+1)):v]format=rgba,fade=t=in:st=0:d=0.3:alpha=1,setpts=PTS+$cs/TB[card];"
fc+="[vc][card]overlay=0:0:eof_action=pass[v];"
fc+="[$n:a]aresample=48000,aformat=channel_layouts=stereo,adelay=${vd_ms}|${vd_ms},volume=$vg,volume=${VO_BOOST:-1}:eval=frame,apad[vo0];"
fc+="[vo0]asplit=2[vo1][vo2];"
fc+="[bed0]volume=0.55,afade=t=out:st=$fe:d=1.2[bed];"
fc+="[bed][vo2]sidechaincompress=threshold=0.02:ratio=8:attack=20:release=400[bd];"
fc+="[bd][vo1]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11[a]"
ffmpeg -v error -y "${inputs[@]}" -i "$vo" -loop 1 -t "$total" -i "$card" -filter_complex "$fc" \
  -map "[v]" -map "[a]" -t "$total" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$out"
echo "$out $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")"
