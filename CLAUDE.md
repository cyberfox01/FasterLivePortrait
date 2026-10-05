# CLAUDE.md

Fork of [warmshao/FasterLivePortrait](https://github.com/warmshao/FasterLivePortrait) (origin: `cyberfox01/FasterLivePortrait`),
run in Docker on two GPUs: RTX 3060 Ti (Ampere, sm_86) and RTX 5060 Ti (Blackwell, sm_120).

## Conventions

- All text in files (code comments, script messages, READMEs, config comments) is in English.
- Match the surrounding code style; keep changes compatible with both TensorRT 8.6 and 10.

## Repository layout

- `run.py`: CLI inference (`--src_image`, `--dri_video`, `--cfg`, `--realtime`, `--animal`, `--paste_back`).
- `api.py`: FastAPI REST API (`POST /predict/`), port from `FLIP_PORT`.
- `webui.py`: Gradio WebUI (`--mode trt|onnx`, default port 9870).
- `configs/trt_infer.yaml` / `configs/onnx_infer.yaml`: model paths per backend (`*_mp_infer.yaml` = MediaPipe variant).
- `src/pipelines/`: inference pipelines. `src/models/`: model wrappers, `predictor.py` holds the TensorRT/ONNX predictors.
- `src/models/XPose/.../ops`: CUDA extension (`MultiScaleDeformableAttention`), only needed for animal mode.
- `scripts/onnx2trt.py`: builds a single TensorRT engine. `scripts/convert_missing_trt.py`: builds all missing engines of a config.
- `docker/`: build environments for both GPUs, see `docker/README.md`.

## Docker

```bash
docker/build.sh rtx5060ti
```

```bash
docker/run.sh rtx5060ti
```

- One shared multi-stage `docker/Dockerfile`; all GPU-specific versions live in `docker/<gpu>/build.args`.
- `rtx3060ti`: CUDA 12.1, cuDNN 8, TensorRT 8.6, torch 2.3.1+cu121, onnxruntime-gpu 1.18.0, `numpy<2`.
- `rtx5060ti`: CUDA 12.9, cuDNN 9, TensorRT 10.16, torch 2.11.0+cu129, onnxruntime-gpu 1.23.2.
- Container entrypoint `docker/start.sh`: builds missing engines, then starts the API (8080) and/or the WebUI (9870).
  Controlled via `FLIP_SERVICES`, `FLIP_CFG`, `FLIP_ANIMAL`, `FLIP_TRT_WORKSPACE_GB`.
- Checkpoints: `/srv/data/AI/FasterLivePortrait.checkpoints`, mounted to `/app/checkpoints`.

Status: `rtx5060ti` is built and verified end to end (~32 ms/frame with `configs/trt_infer.yaml`, API and WebUI work).
`rtx3060ti` has not been built yet. The build host only has the 5060 Ti.

## Gotchas

- **TensorRT engines (`.trt`) are tied to GPU arch + TRT version.** They are written next to the `.onnx` files in the
  checkpoints directory. Don't share one checkpoints directory between both setups; delete the `.trt` files after a TRT update.
- **grid_sample_3d plugin:** the warping model needs the custom `GridSample3D` TensorRT plugin. The images build it
  from SeanWangJS/grid-sample3d-trt-plugin (TRT 10 commit for 5060 Ti, pre-TRT-10 commit for 3060 Ti) and point
  `FLIP_TRT_PLUGIN_PATH` at it. Without that variable the code falls back to the prebuilt `.so` in the checkpoints,
  which does not work on Blackwell.
- **Engine I/O order differs between TRT 8 and 10.** TRT 10 keeps the ONNX order. Fetch multi-output results by
  tensor name, not position (see `motion_extractor_model.py`).
- **onnxruntime:** `insightface` pulls in the CPU `onnxruntime`, which overwrites `onnxruntime-gpu` in the same module
  path. The Dockerfile uninstalls it and reinstalls the GPU package.
- **ONNX backend on the GPU:** stock onnxruntime has no 5-D `GridSample` on CUDA, so with `onnx_infer.yaml` the warping
  falls back to the CPU (~3 s/frame). Use the TensorRT path.
- **Animal mode:** `configs/trt_infer.yaml` expects the v1.1 animal models in `checkpoints/liveportrait_animal_onnx/`,
  but locally they are in `liveportrait_animal_onnx_v1.1/`. The API only checks and converts animal models with `FLIP_ANIMAL=1`.
- **JoyVASA / Kokoro (audio/text driving):** models are not present locally. The WebUI tabs exist but don't work.
- **Disk space:** `/var/lib/docker` and `/srv/data` share one nearly full disk. Check `df -h /var/lib/docker` before
  builds. A full image build needs ~15 GB of temporary space. Don't prune other projects' images or build cache without asking.

## Verification

```bash
docker run --rm --gpus=all -v /srv/data/AI/FasterLivePortrait.checkpoints:/app/checkpoints docker.schlipper.net/faster_liveportrait:rtx5060ti python run.py --src_image assets/examples/source/s10.jpg --dri_video assets/examples/driving/d14.mp4 --cfg configs/trt_infer.yaml
```

Expected: `inference median time` of roughly 30 ms/frame on the 5060 Ti and result videos in `./results/<timestamp>/`.
For the services: `http://<host>:8080/docs` and `http://<host>:9870/` must return HTTP 200.
