#!/bin/bash
##
## Starts the container: docker/run.sh rtx3060ti|rtx5060ti [command...]
##   CHECKPOINTS   model directory (default <repo>/checkpoints, created if missing)
##   FLIP_* variables (see start.sh) are passed through to the container
##
set -e
GPU="${1:?usage: $0 rtx3060ti|rtx5060ti [command...]}"
shift
DOCKER_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "${DOCKER_DIR}/${GPU}/build.args" ]] || { echo "unknown GPU: ${GPU} (expected rtx3060ti or rtx5060ti)" >&2; exit 1; }
IMAGE="${IMAGE:-faster_liveportrait}:${GPU}"
docker image inspect "${IMAGE}" >/dev/null 2>&1 || { echo "image ${IMAGE} not found, build it with docker/build.sh ${GPU}" >&2; exit 1; }
CHECKPOINTS="${CHECKPOINTS:-${DOCKER_DIR}/../checkpoints}"
# create it as the current user, otherwise docker creates an empty root-owned directory
mkdir -p "${CHECKPOINTS}"
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
