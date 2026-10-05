#!/bin/bash
##
## Container entrypoint: build missing TensorRT engines, then start the API and/or WebUI.
##   FLIP_SERVICES  "api webui" (default), "api", "webui" or "live"
##   FLIP_CFG       inference config (default configs/trt_infer.yaml)
##   FLIP_ANIMAL    1 = also build the animal engines and start the API in animal mode
## If one of the services dies, the container exits (wait -n).
## "live" runs alone in the foreground: webcam -> FasterLivePortrait -> v4l2loopback device
##   FLIP_LIVE_SOURCE       source image (default assets/examples/source/s10.jpg)
##   FLIP_LIVE_CAMERA       webcam device (default /dev/video0)
##   FLIP_LIVE_VIRTUAL_CAM  v4l2loopback device (default /dev/video10)
##   FLIP_LIVE_PASTE_BACK   1 = output the full source image instead of the 512x512 face crop
##   FLIP_LIVE_VIRTUAL_CAM_SIZE  e.g. 1280x720: fit the output into this size, blurred fill (default: unchanged)
##
set -e
cd /app

if [[ "${FLIP_CFG}" == *trt* ]]; then
    animal_flag=()
    [[ "${FLIP_ANIMAL}" == "1" ]] && animal_flag=(--animal)
    python3 scripts/convert_missing_trt.py --cfg "${FLIP_CFG}" "${animal_flag[@]}"
    webui_mode=trt
else
    webui_mode=onnx
fi

if [[ "${FLIP_SERVICES}" == "live" ]]; then
    paste_back=()
    [[ "${FLIP_LIVE_PASTE_BACK}" == "1" ]] && paste_back=(--paste_back)
    animal=()
    [[ "${FLIP_ANIMAL}" == "1" ]] && animal=(--animal)
    cam_size=()
    [[ -n "${FLIP_LIVE_VIRTUAL_CAM_SIZE}" ]] && cam_size=(--virtual_cam_size "${FLIP_LIVE_VIRTUAL_CAM_SIZE}")
    exec python3 run.py \
        --src_image "${FLIP_LIVE_SOURCE:-assets/examples/source/s10.jpg}" \
        --dri_video "${FLIP_LIVE_CAMERA:-/dev/video0}" \
        --cfg "${FLIP_CFG}" \
        --realtime --no_preview \
        --virtual_cam "${FLIP_LIVE_VIRTUAL_CAM:-/dev/video10}" \
        "${paste_back[@]}" "${animal[@]}" "${cam_size[@]}"
fi

for service in ${FLIP_SERVICES}; do
    case "${service}" in
        api)   python3 api.py & ;;
        webui) python3 webui.py --mode "${webui_mode}" --host_ip 0.0.0.0 --port 9870 & ;;
        *)     echo "unknown service: ${service}" >&2; exit 1 ;;
    esac
done

wait -n
