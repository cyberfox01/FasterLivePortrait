#!/bin/bash
##
## Builds the image for one GPU: docker/build.sh rtx3060ti|rtx5060ti [further docker build options]
## Versions are defined in docker/<gpu>/build.args.
##
set -e
GPU="${1:?usage: $0 rtx3060ti|rtx5060ti}"
shift
DOCKER_DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS_FILE="${DOCKER_DIR}/${GPU}/build.args"
IMAGE="${IMAGE:-faster_liveportrait}:${GPU}"

[[ -f "${ARGS_FILE}" ]] || { echo "unknown GPU: ${GPU}" >&2; exit 1; }

BUILD_ARGS=()
while IFS= read -r line; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    BUILD_ARGS+=(--build-arg "${line}")
done < "${ARGS_FILE}"

docker build "${BUILD_ARGS[@]}" --tag "${IMAGE}" --file "${DOCKER_DIR}/Dockerfile" "$@" "${DOCKER_DIR}/.."
