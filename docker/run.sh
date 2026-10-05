#!/bin/bash
##
## Starts the container: docker/run.sh rtx3060ti|rtx5060ti [command...]
##   CHECKPOINTS   model directory (default ../checkpoints)
##   FLIP_* variables (see start.sh) are passed through to the container
##
set -e
GPU="${1:?usage: $0 rtx3060ti|rtx5060ti [command...]}"
shift
IMAGE="${IMAGE:-faster_liveportrait}:${GPU}"
CHECKPOINTS="${CHECKPOINTS:-../checkpoints}"
CHECKPOINTS="$(readlink -e "${CHECKPOINTS}")"

ENV_ARGS=()
for var in FLIP_SERVICES FLIP_CFG FLIP_ANIMAL FLIP_TRT_WORKSPACE_GB; do
    [[ -n "${!var}" ]] && ENV_ARGS+=(-e "${var}=${!var}")
done

docker run -it --rm --gpus=all \
    --name faster_liveportrait \
    -p 8080:8080 \
    -p 9870:9870 \
    -v "${CHECKPOINTS}:/app/checkpoints" \
    "${ENV_ARGS[@]}" \
    "${IMAGE}" \
    "$@"
