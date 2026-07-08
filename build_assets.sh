#!/usr/bin/env bash
set -euo pipefail

ROOT="/project/fansa/longe2v_results"
OUT="$ROOT/long_e2v_project_page/assets/videos"
THUMBS="$ROOT/long_e2v_project_page/assets/thumbs"

mkdir -p "$OUT" "$THUMBS" "$OUT/pairs"

encode_seq() {
  local src_dir="$1"
  local start_number="$2"
  local frames="$3"
  local fps="$4"
  local out_file="$5"

  ffmpeg -nostdin -hide_banner -loglevel error -y \
    -framerate "$fps" \
    -start_number "$start_number" \
    -i "$src_dir/%06d.png" \
    -frames:v "$frames" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" \
    -c:v libx264 -preset veryfast -crf 23 -g "$fps" -keyint_min "$fps" -sc_threshold 0 -movflags +faststart -an \
    "$OUT/$out_file"
}

make_thumb() {
  local src_file="$1"
  local out_file="$2"

  ffmpeg -nostdin -hide_banner -loglevel error -y \
    -ss 00:00:01 \
    -i "$OUT/$src_file" \
    -frames:v 1 \
    -vf "scale=240:-1" \
    "$THUMBS/$out_file"
}

make_pair() {
  local left_file="$1"
  local right_file="$2"
  local out_file="$3"

  ffmpeg -nostdin -hide_banner -loglevel error -y \
    -i "$OUT/$left_file" \
    -i "$OUT/$right_file" \
    -filter_complex "[0:v]setsar=1[left];[1:v]setsar=1[right];[left][right]hstack=inputs=2,format=yuv420p[v]" \
    -map "[v]" \
    -c:v libx264 -preset veryfast -crf 24 -movflags +faststart -an \
    "$OUT/pairs/$out_file"
}

make_result_pairs() {
  local prefix="$1"
  shift

  local suffix
  for suffix in "$@"; do
    make_pair "${prefix}_ours.mp4" "${prefix}_${suffix}.mp4" "${prefix}_ours__${prefix}_${suffix}.mp4"
  done
}

encode_recon_hqf() {
  local prefix="$1"
  local scene="$2"
  local frames="$3"
  local baselines=(
    "e2vid:E2VID"
    "e2vidplus:E2VID+"
    "firenet:FireNet"
    "firenetplus:FireNet+"
    "etnet:ET-Net"
    "spade:SPADE-E2VID"
    "ssl:SSL-E2VID"
    "hypere2vid:HyperE2VID"
  )

  encode_seq "/project3/fansa/event_diffusion/eval_dataset/HQF/$scene/event_images" 0 "$frames" 30 "${prefix}_events.mp4"
  encode_seq "$ROOT/recon_pred/HQF/Ours_recon/$scene" 1 "$frames" 30 "${prefix}_ours.mp4"

  local item key method
  for item in "${baselines[@]}"; do
    key="${item%%:*}"
    method="${item#*:}"
    encode_seq "$ROOT/recon_pred/HQF/$method/$scene" 1 "$frames" 30 "${prefix}_${key}.mp4"
  done
}

encode_recon_mvsec() {
  local prefix="$1"
  local scene="$2"
  local event_start="$3"
  local frames="$4"
  local baseline_start=$((event_start + 1))
  local baselines=(
    "e2vid:E2VID"
    "e2vidplus:E2VID+"
    "firenet:FireNet"
    "firenetplus:FireNet+"
    "etnet:ET-Net"
    "spade:SPADE-E2VID"
    "ssl:SSL-E2VID"
    "hypere2vid:HyperE2VID"
  )

  encode_seq "/project3/fansa/event_diffusion/eval_dataset/mvsec_eval/$scene/event_images_eval" "$event_start" "$frames" 30 "${prefix}_events.mp4"
  encode_seq "$ROOT/recon_pred/MVSEC/Ours_recon/$scene" 1 "$frames" 30 "${prefix}_ours.mp4"

  local item key method
  for item in "${baselines[@]}"; do
    key="${item%%:*}"
    method="${item#*:}"
    encode_seq "$ROOT/recon_pred/MVSEC/$method/$scene" "$baseline_start" "$frames" 30 "${prefix}_${key}.mp4"
  done
}

encode_pred_hqf() {
  local prefix="$1"
  local scene="$2"
  local frames="$3"

  encode_seq "/project3/fansa/event_diffusion/eval_dataset/HQF/$scene/event_images" 0 "$frames" 30 "${prefix}_events.mp4"
  encode_seq "$ROOT/recon_pred/HQF/Ours_pred/$scene" 1 "$frames" 30 "${prefix}_ours.mp4"
  encode_seq "$ROOT/recon_pred/HQF/VDM-EVFI/$scene" 1 "$frames" 30 "${prefix}_vdm_evfi.mp4"
}

encode_pred_mvsec() {
  local prefix="$1"
  local scene="$2"
  local event_start="$3"
  local frames="$4"

  encode_seq "/project3/fansa/event_diffusion/eval_dataset/mvsec_eval/$scene/event_images_eval" "$event_start" "$frames" 30 "${prefix}_events.mp4"
  encode_seq "$ROOT/recon_pred/MVSEC/Ours_pred/$scene" 1 "$frames" 30 "${prefix}_ours.mp4"
  encode_seq "$ROOT/recon_pred/MVSEC/VDM-EVFI/$scene" 1 "$frames" 30 "${prefix}_vdm_evfi.mp4"
}

encode_pred_ecd() {
  local prefix="$1"
  local scene="$2"
  local event_start="$3"
  local frames="$4"

  encode_seq "/project3/fansa/event_diffusion/eval_dataset/ECD/$scene/event_images_eval" "$event_start" "$frames" 30 "${prefix}_events.mp4"
  encode_seq "$ROOT/recon_pred/ECD/Ours_pred/$scene" 1 "$frames" 30 "${prefix}_ours.mp4"
  encode_seq "$ROOT/recon_pred/ECD/VDM-EVFI/$scene" 1 "$frames" 30 "${prefix}_vdm_evfi.mp4"
}

encode_sparse_by_reference() {
  local src_dir="$1"
  local ref_dir="$2"
  local index_offset="$3"
  local fps="$4"
  local out_file="$5"
  local tmp_dir frames

  tmp_dir=$(mktemp -d)
  frames=$(python3 - "$src_dir" "$ref_dir" "$index_offset" "$tmp_dir" <<'PYSPARSE'
from pathlib import Path
import os
import sys

src_dir = Path(sys.argv[1])
ref_dir = Path(sys.argv[2])
index_offset = int(sys.argv[3])
tmp_dir = Path(sys.argv[4])
refs = sorted(ref_dir.glob("*.png"))
if not refs:
    raise SystemExit(f"No PNG frames found in {ref_dir}")

for out_idx, ref_path in enumerate(refs):
    src_idx = int(ref_path.stem) + index_offset
    src_path = src_dir / f"{src_idx:06d}.png"
    if not src_path.exists():
        raise SystemExit(f"Missing source frame {src_path}")
    os.symlink(src_path, tmp_dir / f"{out_idx:06d}.png")

print(len(refs))
PYSPARSE
)

  encode_seq "$tmp_dir" 0 "$frames" "$fps" "$out_file"
  rm -rf "$tmp_dir"
}

encode_interp_bs() {
  local prefix="$1"
  local scene="$2"
  local ref_dir="$ROOT/interpolation/BS-ERGB/Ours/$scene"

  encode_sparse_by_reference "/project2/fansa/event_diffusion/train_dataset/bs_ergb/1_TEST_interpolation/$scene/event_images" "$ref_dir" -1 12 "${prefix}_events.mp4"
  encode_sparse_by_reference "$ROOT/interpolation/BS-ERGB/Ours/$scene" "$ref_dir" 0 12 "${prefix}_ours.mp4"
  encode_sparse_by_reference "$ROOT/interpolation/BS-ERGB/CBMNet-Large/$scene" "$ref_dir" 0 12 "${prefix}_cbmnet.mp4"
  encode_sparse_by_reference "$ROOT/interpolation/BS-ERGB/TLXNet+/$scene" "$ref_dir" 0 12 "${prefix}_tlxnet.mp4"
}

cp "$ROOT/long_e2v_project_page/teaser video.mp4" "$OUT/teaser.mp4"

# What-can-it-do demos.
encode_seq "$ROOT/recon_pred/HQF/Ours_recon/bike_bay_hdr" 1 180 30 "demo_reconstruction.mp4"
encode_seq "$ROOT/recon_pred/HQF/Ours_pred/desk_fast" 1 180 30 "demo_prediction.mp4"
encode_seq "$ROOT/interpolation/BS-ERGB/Ours/basket_08" 1 31 12 "demo_interpolation.mp4"

# Full-length Reconstruction results.
encode_recon_hqf "recon_bike" "bike_bay_hdr" 2429
encode_recon_hqf "recon_boxes" "boxes" 538
encode_recon_hqf "recon_desk" "desk" 1489
encode_recon_hqf "recon_posters" "engineering_posters" 1265
encode_recon_hqf "recon_pillar2" "poster_pillar_2" 611
encode_recon_hqf "recon_reflective" "reflective_materials" 617
encode_recon_mvsec "recon_indoor" "indoor_flying1_data" 314 1882
encode_recon_hqf "recon_stilllife" "still_life" 1192

# Full-length Prediction results.
encode_pred_hqf "pred_slowfast" "slow_and_fast_desk" 1742
encode_pred_hqf "pred_pillar1" "poster_pillar_1" 996
encode_pred_hqf "pred_slowhand" "slow_hand" 899
encode_pred_hqf "pred_deskslow" "desk_slow" 1432
encode_pred_mvsec "pred_indoor2" "indoor_flying2_data" 314 1882
encode_pred_ecd "pred_calibration" "calibration" 119 356
encode_pred_ecd "pred_shapes" "shapes_6dof" 114 339
encode_pred_ecd "pred_office" "office_zigzag" 114 132

# Frame Interpolation results.
encode_interp_bs "interp_basket" "basket_08"
encode_interp_bs "interp_horse" "horse_11"
encode_interp_bs "interp_elastic" "elastic_bands_01"
encode_interp_bs "interp_football" "football_04"
encode_interp_bs "interp_water_tank" "may29_water_tank_pouring_02"
encode_interp_bs "interp_ball" "ball_06"
encode_interp_bs "interp_fire" "fire_02"
encode_interp_bs "interp_rope" "rope_jumping_01"

make_thumb "recon_bike_ours.mp4" "recon_bike_thumb.png"
make_thumb "recon_boxes_ours.mp4" "recon_boxes_thumb.png"
make_thumb "recon_desk_ours.mp4" "recon_desk_thumb.png"
make_thumb "recon_posters_ours.mp4" "recon_posters_thumb.png"
make_thumb "recon_pillar2_ours.mp4" "recon_pillar2_thumb.png"
make_thumb "recon_reflective_ours.mp4" "recon_reflective_thumb.png"
make_thumb "recon_indoor_ours.mp4" "recon_indoor_thumb.png"
make_thumb "recon_stilllife_ours.mp4" "recon_stilllife_thumb.png"
make_thumb "pred_slowfast_ours.mp4" "pred_slowfast_thumb.png"
make_thumb "pred_pillar1_ours.mp4" "pred_pillar1_thumb.png"
make_thumb "pred_slowhand_ours.mp4" "pred_slowhand_thumb.png"
make_thumb "pred_deskslow_ours.mp4" "pred_deskslow_thumb.png"
make_thumb "pred_indoor2_ours.mp4" "pred_indoor2_thumb.png"
make_thumb "pred_calibration_ours.mp4" "pred_calibration_thumb.png"
make_thumb "pred_shapes_ours.mp4" "pred_shapes_thumb.png"
make_thumb "pred_office_ours.mp4" "pred_office_thumb.png"
make_thumb "interp_basket_ours.mp4" "interp_basket_thumb.png"
make_thumb "interp_horse_ours.mp4" "interp_horse_thumb.png"
make_thumb "interp_elastic_ours.mp4" "interp_elastic_thumb.png"
make_thumb "interp_football_ours.mp4" "interp_football_thumb.png"
make_thumb "interp_water_tank_ours.mp4" "interp_water_tank_thumb.png"
make_thumb "interp_ball_ours.mp4" "interp_ball_thumb.png"
make_thumb "interp_fire_ours.mp4" "interp_fire_thumb.png"
make_thumb "interp_rope_ours.mp4" "interp_rope_thumb.png"


# Single-clock paired videos for the canvas swipe viewer.
recon_suffixes=(events e2vid e2vidplus firenet firenetplus etnet spade ssl hypere2vid)
pred_suffixes=(events vdm_evfi)
interp_suffixes=(events cbmnet tlxnet)

for prefix in recon_bike recon_boxes recon_desk recon_posters recon_pillar2 recon_reflective recon_indoor recon_stilllife; do
  make_result_pairs "$prefix" "${recon_suffixes[@]}"
done

for prefix in pred_slowfast pred_pillar1 pred_slowhand pred_deskslow pred_indoor2 pred_calibration pred_shapes pred_office; do
  make_result_pairs "$prefix" "${pred_suffixes[@]}"
done

for prefix in interp_basket interp_horse interp_elastic interp_football interp_water_tank interp_ball interp_fire interp_rope; do
  make_result_pairs "$prefix" "${interp_suffixes[@]}"
done

echo "LongE2V web assets written to $OUT"
