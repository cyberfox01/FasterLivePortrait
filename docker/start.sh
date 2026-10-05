#!/bin/bash
##
## Container entrypoint: build missing TensorRT engines, then start the API and/or WebUI.
##   FLIP_SERVICES  "api webui" (default), "api" or "webui"
##   FLIP_CFG       inference config (default configs/trt_infer.yaml)
##   FLIP_ANIMAL    1 = also build the animal engines and start the API in animal mode
## If one of the services dies, the container exits (wait -n).
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

for service in ${FLIP_SERVICES}; do
    case "${service}" in
        api)   python3 api.py & ;;
        webui) python3 webui.py --mode "${webui_mode}" --host_ip 0.0.0.0 --port 9870 & ;;
        *)     echo "unknown service: ${service}" >&2; exit 1 ;;
    esac
done

wait -n
