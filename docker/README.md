# Docker Build Environments

Two images, because the two GPUs need different CUDA/TensorRT stacks:

| Setup | GPU | Arch | CUDA | cuDNN | TensorRT | Torch | onnxruntime-gpu |
|---|---|---|---|---|---|---|---|
| `rtx3060ti` | RTX 3060 Ti (Ampere) | sm_86 | 12.1 | 8 | 8.6.1 | 2.3.1+cu121 | 1.18.0 |
| `rtx5060ti` | RTX 5060 Ti (Blackwell) | sm_120 | 12.9 | 9 | 10.16 | 2.11.0+cu129 | 1.23.2 |

Blackwell requires at least CUDA 12.8 / TensorRT 10.8. The 3060 Ti stays on the upstream stack (TRT 8.6).

Verification status:

- `rtx5060ti`: built and tested. Engines build, `run.py` with `configs/trt_infer.yaml` runs at ~32 ms/frame,
  and both the API (`POST /predict/`) and the WebUI respond.
- `rtx3060ti`: not built yet (no Ampere card in the build machine). The Python dependencies resolve cleanly
  in a dry run.

## Layout

- `Dockerfile`: shared multi-stage Dockerfile. The `builder` stage (CUDA devel + TRT headers) compiles
  everything that needs nvcc into a venv. The `runtime` stage (CUDA runtime + TRT runtime) only takes over the results.
- `<gpu>/build.args`: all GPU-specific versions (base images, TRT, torch, ORT, CUDA arch).
- `build.sh` / `run.sh`: build and run, `live.sh`: live mode with webcam, `start.sh`: container entrypoint.

Both images build:

- the `grid_sample_3d` TensorRT plugin ([SeanWangJS/grid-sample3d-trt-plugin](https://github.com/SeanWangJS/grid-sample3d-trt-plugin))
  for the matching TRT version and GPU arch, into `/opt/grid-sample3d-trt-plugin/` (set via `FLIP_TRT_PLUGIN_PATH`,
  so the precompiled `.so` from the checkpoints is not used),
- the XPose CUDA ops (`MultiScaleDeformableAttention`) for animal mode.

## Build and run

```bash
docker/build.sh rtx5060ti
```

```bash
docker/run.sh rtx5060ti
```

- REST API: `http://<host>:8080/docs`
- Gradio WebUI: `http://<host>:9870/`

The checkpoints are mounted from `CHECKPOINTS` (default `checkpoints/` in the repo, created if missing) to
`/app/checkpoints`. On start, `scripts/convert_missing_trt.py` builds all missing `.trt` engines next to the
`.onnx` files. The first start takes a few minutes.

**Note:** Engines only work for the GPU arch and TRT version they were built with. If both machines share
one checkpoint directory, each setup needs its own copy (via `CHECKPOINTS=...`). After a TRT update, delete
the `.trt` files and they will be rebuilt.

## Live mode (webcam -> virtual camera)

```bash
docker/live.sh rtx5060ti /path/to/source.jpg
```

Drives the source image with the webcam and sends the result to a v4l2loopback device that browsers and video
conferencing apps can use as a camera ("FasterLivePortrait"). If `/dev/video10` does not exist yet, the script loads
`v4l2loopback` via `sudo modprobe` (`exclusive_caps=1`). Stop with Ctrl+C.

| Variable | Default | Meaning |
|---|---|---|
| `CAMERA` | `/dev/video0` | webcam device |
| `VIRTUAL_CAM_NR` | `10` | v4l2loopback device number (`/dev/video10`) |
| `PASTE_BACK` | `0` | `1` = output the full source image instead of the 512x512 face crop |

Without a source image, `assets/examples/source/s10.jpg` is used. Outside Docker the same works with
`run.py --dri_video /dev/video0 --realtime --virtual_cam /dev/video10 [--no_preview]`.

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `FLIP_SERVICES` | `api webui` | which services to start (`api`, `webui` or both, or `live` alone, see above) |
| `FLIP_CFG` | `configs/trt_infer.yaml` | inference config. `configs/onnx_infer.yaml` uses onnxruntime (warping then runs on the CPU, slow) |
| `FLIP_ANIMAL` | `0` | `1` = also build the animal engines, API starts in animal mode |
| `FLIP_TRT_WORKSPACE_GB` | `12` | TensorRT workspace for building engines |

Example, WebUI only:

```bash
FLIP_SERVICES=webui docker/run.sh rtx3060ti
```

A shell in the container:

```bash
docker/run.sh rtx5060ti bash
```

## Code changes (shared by both setups)

- `scripts/onnx2trt.py`: works with TensorRT 8.6 and 10 (workspace limit, `STRICT_TYPES`, explicit batch,
  `build_serialized_network`).
- `scripts/convert_missing_trt.py`: builds only missing engines, `motion_extractor` in fp32 as in `all_onnx2trt.sh`.
- `src/models/predictor.py`, `scripts/onnx2trt.py`: plugin path via `FLIP_TRT_PLUGIN_PATH`.
- `api.py`: `FLIP_CFG`, `FLIP_ANIMAL`, `FLIP_PORT` as int. Animal models are only checked and converted with
  `FLIP_ANIMAL=1`, and the download uses `hf download` instead of the deprecated `huggingface-cli`.
- `src/models/motion_extractor_model.py`: TRT outputs are fetched by name instead of position, because TRT 8 and 10
  order the engine outputs differently.
- `requirements.txt`: added `colorama` (imported by `run.py`) and `pyvirtualcam` (live mode).
- `run.py`: `--dri_video` accepts a camera index or `/dev/videoN`, `--virtual_cam` sends the realtime output to a
  v4l2loopback device, `--no_preview` disables the OpenCV window, Ctrl+C stops cleanly.
- `webui.py`: also starts without `checkpoints/Kokoro-82M/voices/`.
- XPose ops: `setup.py` builds without a visible GPU (`FORCE_CUDA=1`, arch via `TORCH_CUDA_ARCH_LIST`), CUDA code
  adapted to the current torch API (`scalar_type()`, `data_ptr<T>()`).

## Animal mode

`configs/trt_infer.yaml` expects the v1.1 animal models in `checkpoints/liveportrait_animal_onnx/`
(e.g. `warping_spade-fix-v1.1.onnx`). If they are in `liveportrait_animal_onnx_v1.1/`, copy them over first,
otherwise building the engines with `FLIP_ANIMAL=1` fails.
