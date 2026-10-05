# -*- coding: utf-8 -*-
"""
Build all TensorRT engines referenced by a trt config that don't exist yet.
Engines are specific to GPU architecture and TensorRT version, so this runs on container start.

usage: python scripts/convert_missing_trt.py [--cfg configs/trt_infer.yaml] [--animal]
"""
import argparse
import os
import subprocess
import sys

from omegaconf import OmegaConf

# models that must be built in fp32 (see scripts/all_onnx2trt*.sh)
FP32_MODELS = ("motion_extractor",)


def iter_model_paths(models):
    for name in models:
        paths = models[name].model_path
        for path in ([paths] if isinstance(paths, str) else paths):
            yield name, path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cfg", default="configs/trt_infer.yaml")
    parser.add_argument("--animal", action="store_true", help="also build the animal model engines")
    args = parser.parse_args()

    cfg = OmegaConf.load(args.cfg)
    model_groups = [cfg.models]
    if args.animal:
        model_groups.append(cfg.animal_models)

    failed = False
    for models in model_groups:
        for name, trt_path in iter_model_paths(models):
            if not trt_path.endswith(".trt") or os.path.exists(trt_path):
                continue
            onnx_path = trt_path[:-4] + ".onnx"
            if not os.path.exists(onnx_path):
                print(f"[convert_missing_trt] missing onnx model: {onnx_path}", file=sys.stderr)
                failed = True
                continue
            cmd = [sys.executable, "scripts/onnx2trt.py", "-o", onnx_path]
            if name in FP32_MODELS:
                cmd += ["-p", "fp32"]
            print(f"[convert_missing_trt] {' '.join(cmd)}", flush=True)
            if subprocess.run(cmd).returncode != 0:
                failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
