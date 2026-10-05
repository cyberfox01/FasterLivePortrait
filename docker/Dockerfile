# FasterLivePortrait with TensorRT, shared Dockerfile for all GPU setups.
# GPU-specific versions come from docker/<gpu>/build.args, build with:
#   docker/build.sh rtx3060ti|rtx5060ti
# The build context is the repo root.
#
# Stage "builder" (CUDA devel + TensorRT headers) compiles everything that needs nvcc:
#   grid_sample_3d TensorRT plugin, XPose CUDA ops, pycuda and the Python venv.
# Stage "runtime" (CUDA runtime + TensorRT runtime) only takes over the results.

# No real defaults, docker/build.sh passes them from build.args. The placeholders only keep
# BuildKit's InvalidDefaultArgInFrom check quiet and make a build without build.args fail clearly.
ARG CUDA_DEVEL_IMAGE=set-cuda-devel-image-via-build-args
ARG CUDA_RUNTIME_IMAGE=set-cuda-runtime-image-via-build-args

########################################################################################
FROM ${CUDA_DEVEL_IMAGE} AS builder

ARG TRT_MAJOR
ARG TRT_VERSION
ARG TRT_EXTRA_DEV_PKGS=""
ARG TORCH_INDEX
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION
ARG ORT_VERSION
# additional pip constraints, space-separated (e.g. "numpy<2")
ARG EXTRA_CONSTRAINTS=""
# CUDA architecture in CMake notation (86) and torch notation (8.6)
ARG CUDA_ARCH
ARG TORCH_CUDA_ARCH_LIST
ARG GRID_SAMPLE_PLUGIN_REF

ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        git python3-dev python3-venv \
        libnvinfer${TRT_MAJOR}=${TRT_VERSION} libnvinfer-plugin${TRT_MAJOR}=${TRT_VERSION} \
        libnvinfer-dev=${TRT_VERSION} libnvinfer-headers-dev=${TRT_VERSION} \
        libnvinfer-headers-plugin-dev=${TRT_VERSION} \
        $(for p in ${TRT_EXTRA_DEV_PKGS}; do echo "$p=${TRT_VERSION}"; done) \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --upgrade pip setuptools wheel cmake
ENV PATH=/opt/venv/bin:$PATH

# grid_sample_3d TensorRT plugin for exactly this TRT version/GPU.
# The pre-TRT-10 revision uses ${CUDAToolkit_INCLUDE_DIR}, which current CMake no longer sets
# (cuda_fp16.h not found); upstream later switched to ${CUDAToolkit_INCLUDE_DIRS}, do the same here.
RUN git clone https://github.com/SeanWangJS/grid-sample3d-trt-plugin /opt/grid-sample3d-trt-plugin \
    && cd /opt/grid-sample3d-trt-plugin && git checkout ${GRID_SAMPLE_PLUGIN_REF} \
    && sed -i "s/CUDA_ARCHITECTURES \"[^\"]*\"/CUDA_ARCHITECTURES \"${CUDA_ARCH}\"/" CMakeLists.txt test/CMakeLists.txt \
    && sed -i 's/\${CUDAToolkit_INCLUDE_DIR}/${CUDAToolkit_INCLUDE_DIRS}/' CMakeLists.txt test/CMakeLists.txt \
    && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --target grid_sample_3d_plugin -j"$(nproc)"

# pin torch/ORT/gradio so requirements.txt doesn't replace them
RUN printf "torch==${TORCH_VERSION}\ntorchvision==${TORCHVISION_VERSION}\ntorchaudio==${TORCHAUDIO_VERSION}\nonnxruntime-gpu==${ORT_VERSION}\ngradio<6\n" > /opt/venv/constraints.txt \
    && for c in ${EXTRA_CONSTRAINTS}; do echo "$c" >> /opt/venv/constraints.txt; done \
    && pip install --index-url ${TORCH_INDEX} \
        torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCHAUDIO_VERSION}
COPY requirements.txt /tmp/requirements.txt
RUN pip install -c /opt/venv/constraints.txt -r /tmp/requirements.txt \
        onnxruntime-gpu fastapi uvicorn python-multipart \
    # insightface pulls in the CPU onnxruntime, which overwrites the GPU package in the same module path
    && pip uninstall -y onnxruntime \
    && pip install --force-reinstall --no-deps onnxruntime-gpu==${ORT_VERSION}

# XPose CUDA ops (animal mode)
COPY src/models/XPose/models/UniPose/ops /tmp/xpose-ops
RUN cd /tmp/xpose-ops \
    && FORCE_CUDA=1 TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}" pip install --no-build-isolation . \
    && rm -rf /tmp/xpose-ops

########################################################################################
FROM ${CUDA_RUNTIME_IMAGE} AS runtime

ARG TRT_MAJOR
ARG TRT_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# TensorRT runtime incl. builder (engines are built inside the container on first start)
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 ffmpeg espeak-ng libgl1 libglib2.0-0 \
        libnvinfer${TRT_MAJOR}=${TRT_VERSION} libnvinfer-plugin${TRT_MAJOR}=${TRT_VERSION} \
        libnvonnxparsers${TRT_MAJOR}=${TRT_VERSION} libnvinfer-vc-plugin${TRT_MAJOR}=${TRT_VERSION} \
        python3-libnvinfer=${TRT_VERSION} \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/grid-sample3d-trt-plugin/build/libgrid_sample_3d_plugin.so /opt/grid-sample3d-trt-plugin/
# make the tensorrt Python module from the apt package visible in the venv
RUN printf '/usr/lib/python3.10/dist-packages\n/usr/lib/python3/dist-packages\n' > /opt/venv/lib/python3.10/site-packages/system-tensorrt.pth \
    && ln -s /opt/venv/bin/python /usr/local/bin/python

WORKDIR /app
COPY . /app

ENV PATH=/opt/venv/bin:$PATH \
    FLIP_TRT_PLUGIN_PATH=/opt/grid-sample3d-trt-plugin/libgrid_sample_3d_plugin.so \
    FLIP_IP=0.0.0.0 \
    FLIP_PORT=8080 \
    FLIP_CHECKPOINT_DIR=/app/checkpoints \
    FLIP_CFG=configs/trt_infer.yaml \
    FLIP_ANIMAL=0 \
    FLIP_SERVICES="api webui"

# 8080 = REST-API, 9870 = Gradio-WebUI
EXPOSE 8080 9870
CMD ["bash", "/app/docker/start.sh"]
