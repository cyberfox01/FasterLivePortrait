#!/bin/bash
##
## Live mode: webcam -> FasterLivePortrait -> v4l2loopback virtual camera
##   docker/live.sh rtx3060ti|rtx5060ti [source image]
##   CAMERA          webcam device (default /dev/video0)
##   VIRTUAL_CAM_NR  number of the v4l2loopback device (default 10 -> /dev/video10)
##   PASTE_BACK      1 = output the full source image instead of the 512x512 face crop
##   CHECKPOINTS     model directory (default /srv/data/AI/FasterLivePortrait.checkpoints)
## Loads the v4l2loopback kernel module via sudo if the virtual camera does not exist yet.
## Stop with Ctrl+C.
##
set -e
GPU="${1:?usage: $0 rtx3060ti|rtx5060ti [source image]}"
SOURCE="$2"
IMAGE="${IMAGE:-faster_liveportrait}:${GPU}"
CHECKPOINTS="${CHECKPOINTS:-/srv/data/AI/FasterLivePortrait.checkpoints}"
CAMERA="${CAMERA:-/dev/video0}"
VIRTUAL_CAM_NR="${VIRTUAL_CAM_NR:-10}"
VIRTUAL_CAM="/dev/video${VIRTUAL_CAM_NR}"

[[ -e "${CAMERA}" ]] || { echo "webcam ${CAMERA} not found" >&2; exit 1; }

if [[ ! -e "${VIRTUAL_CAM}" ]]; then
    echo "loading v4l2loopback for ${VIRTUAL_CAM} (needs sudo)"
    # exclusive_caps=1: browsers and video conferencing apps only list capture-only devices
    sudo modprobe v4l2loopback devices=1 video_nr="${VIRTUAL_CAM_NR}" card_label="FasterLivePortrait" exclusive_caps=1
fi
if [[ ! -e "${VIRTUAL_CAM}" ]]; then
    echo "${VIRTUAL_CAM} still missing: v4l2loopback is probably loaded with other devices already" >&2
    echo "unload it with 'sudo modprobe -r v4l2loopback' and try again" >&2
    exit 1
fi

ARGS=(-e FLIP_SERVICES=live -e "FLIP_LIVE_CAMERA=${CAMERA}" -e "FLIP_LIVE_VIRTUAL_CAM=${VIRTUAL_CAM}")
[[ "${PASTE_BACK}" == "1" ]] && ARGS+=(-e FLIP_LIVE_PASTE_BACK=1)
[[ -n "${FLIP_ANIMAL}" ]] && ARGS+=(-e "FLIP_ANIMAL=${FLIP_ANIMAL}")
if [[ -n "${SOURCE}" ]]; then
    [[ -f "${SOURCE}" ]] || { echo "source image ${SOURCE} not found" >&2; exit 1; }
    SOURCE_DIR="$(cd "$(dirname "${SOURCE}")" && pwd)"
    ARGS+=(-v "${SOURCE_DIR}:/input:ro" -e "FLIP_LIVE_SOURCE=/input/$(basename "${SOURCE}")")
fi

# --init forwards Ctrl+C to run.py, which then closes the camera devices cleanly
docker run -it --rm --init --gpus=all \
    --name faster_liveportrait_live \
    --device "${CAMERA}" \
    --device "${VIRTUAL_CAM}" \
    -v "${CHECKPOINTS}:/app/checkpoints" \
    "${ARGS[@]}" \
    "${IMAGE}"
