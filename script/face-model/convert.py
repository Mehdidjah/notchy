"""Convert dlib's face-recognition ResNet into a Core ML ML Program for Face Check.

    python3 -I script/face-model/convert.py \
        --dat /path/to/dlib_face_recognition_resnet_model_v1.dat \
        --out Resources/FaceCheck/FaceDescriptor.mlpackage

The graph is built directly with coremltools' MIL builder from the numpy weights that
dlibnet.py reads, so no deep-learning framework is needed. The model takes a 150x150 RGB
image (a face chip aligned the way dlib's get_face_chip_details(shape, 150, 0.25) does it)
and returns dlib's 128-number face descriptor. Two descriptors closer than 0.6 (Euclidean)
are, by dlib's convention, the same person.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402

import dlibnet  # noqa: E402

# SHA-256 of the decompressed model this converter was written and checked against
# (dlib.net/files and github.com/davisking/dlib-models serve the same bytes).
KNOWN_SOURCE_SHA256 = "55533b28a95800a551ba546ba62fe69625c7e95a7061c338adffead08719da30"
MODEL_IDENTIFIER = "dlib-face-resnet-v1"
INPUT_NAME = "image"
OUTPUT_NAME = "descriptor"


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fold_affines(net: dlibnet.FaceNet) -> list:
    """Merge every affine layer into the convolution right before it (exact algebra)."""
    folded = []
    for layer in net.layers:
        previous = folded[-1] if folded else None
        if (isinstance(layer, dlibnet.Affine) and isinstance(previous, dlibnet.Conv)
                and not previous.fused_relu):
            scale = layer.scale.astype(np.float64)
            weight = previous.weight.astype(np.float64) * scale[:, None, None, None]
            bias = np.zeros_like(scale) if previous.bias is None else previous.bias.astype(np.float64)
            folded[-1] = dlibnet.Conv(
                weight=weight.astype(np.float32),
                bias=(bias * scale + layer.shift.astype(np.float64)).astype(np.float32),
                stride=previous.stride,
                padding=previous.padding,
            )
        else:
            folded.append(layer)
    return folded


def build_program(net: dlibnet.FaceNet):
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.mil import types
    import coremltools as ct

    layers = fold_affines(net)
    size = dlibnet.CHIP_SIZE

    def pad_to(x, shape):
        # dlib adds tensors of different sizes as if the smaller one had zeros appended.
        extra = [t - s for s, t in zip(x.shape, shape)]
        if not any(extra):
            return x
        if extra[0]:
            raise ValueError("batch sizes never differ in this network")
        return mb.pad(x=x, pad=np.array([0, extra[1], 0, extra[2], 0, extra[3]], dtype=np.int32),
                      mode="constant", constant_val=0.0)

    @mb.program(input_specs=[mb.TensorSpec(shape=(1, 3, size, size), dtype=types.fp32)],
                opset_version=ct.target.macOS14)
    def program(image):
        x = image
        tagged = {}
        for layer in layers:
            if isinstance(layer, dlibnet.Tag):
                tagged[layer.number] = x
            elif isinstance(layer, dlibnet.Skip):
                x = tagged[layer.number]
            elif isinstance(layer, dlibnet.AddPrev):
                other = tagged[layer.number]
                shape = tuple(max(a, b) for a, b in zip(x.shape, other.shape))
                x = mb.add(x=pad_to(x, shape), y=pad_to(other, shape))
            elif isinstance(layer, dlibnet.Conv):
                pad_y, pad_x = layer.padding
                x = mb.conv(x=x, weight=layer.weight, bias=layer.bias,
                            strides=list(layer.stride), pad_type="custom",
                            pad=[pad_y, pad_y, pad_x, pad_x])
                if layer.fused_relu:
                    x = mb.relu(x=x)
            elif isinstance(layer, dlibnet.Affine):
                channels = layer.scale.size
                x = mb.mul(x=x, y=layer.scale.reshape(1, channels, 1, 1))
                x = mb.add(x=x, y=layer.shift.reshape(1, channels, 1, 1))
            elif isinstance(layer, dlibnet.Relu):
                x = mb.relu(x=x)
            elif isinstance(layer, dlibnet.Pool):
                if layer.window == (0, 0):
                    reduce = mb.reduce_max if layer.kind == "max" else mb.reduce_mean
                    x = reduce(x=x, axes=[2, 3], keep_dims=True)
                else:
                    if layer.padding != (0, 0):
                        raise NotImplementedError("padded pooling is not used by this network")
                    pool = mb.max_pool if layer.kind == "max" else mb.avg_pool
                    x = pool(x=x, kernel_sizes=list(layer.window), strides=list(layer.stride),
                             pad_type="valid")
            elif isinstance(layer, dlibnet.Dense):
                x = mb.reshape(x=x, shape=[1, -1])
                x = mb.linear(x=x, weight=layer.weight.T.copy(),
                              bias=None if layer.bias is None else layer.bias)
            else:
                raise AssertionError(type(layer))
        return mb.identity(x=x, name=OUTPUT_NAME)

    return program


def convert(net: dlibnet.FaceNet, precision: str, source_sha256: str):
    import coremltools as ct

    means = net.input.channel_means
    image_input = ct.ImageType(
        name=INPUT_NAME,
        shape=(1, 3, dlibnet.CHIP_SIZE, dlibnet.CHIP_SIZE),
        scale=1.0 / 256.0,
        bias=[float(-m / 256.0) for m in means],
        color_layout=ct.colorlayout.RGB,
        channel_first=True,
    )
    model = ct.convert(
        build_program(net),
        convert_to="mlprogram",
        inputs=[image_input],
        compute_precision=ct.precision.FLOAT16 if precision == "fp16" else ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
    )
    model.author = "Davis King (dlib); converted for Notchy"
    model.license = "Public domain (see github.com/davisking/dlib-models)"
    model.short_description = (
        "dlib_face_recognition_resnet_model_v1: 150x150 aligned RGB face chip in, "
        "128-number face descriptor out. Same person when Euclidean distance < 0.6."
    )
    model.version = "1"
    model.input_description[INPUT_NAME] = (
        "150x150 RGB face chip aligned like dlib's get_face_chip_details(shape, 150, 0.25)"
    )
    model.output_description[OUTPUT_NAME] = "128-d face descriptor (not normalised)"
    model.user_defined_metadata.update({
        "notchy.faceModel.identifier": MODEL_IDENTIFIER,
        "notchy.faceModel.precision": precision,
        "notchy.faceModel.descriptorLength": str(dlibnet.DESCRIPTOR_LENGTH),
        "notchy.faceModel.sameFaceDistance": f"{net.loss_distance_threshold:g}",
        "notchy.faceModel.sourceFile": "dlib_face_recognition_resnet_model_v1.dat",
        "notchy.faceModel.sourceSHA256": source_sha256,
        "notchy.faceModel.channelMeans": ",".join(f"{m:.6g}" for m in means),
    })
    return model


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dat", required=True, help="decompressed dlib_face_recognition_resnet_model_v1.dat")
    parser.add_argument("--out", required=True, help="output .mlpackage path")
    parser.add_argument("--precision", choices=("fp16", "fp32"), default="fp16")
    parser.add_argument("--allow-unknown-source", action="store_true",
                        help="convert even if the .dat file's SHA-256 is not the known one")
    args = parser.parse_args()

    source_sha256 = sha256_of(args.dat)
    print(f"source {args.dat}\n  sha256 {source_sha256}")
    if source_sha256 != KNOWN_SOURCE_SHA256 and not args.allow_unknown_source:
        print("  not the file this converter was checked against; pass --allow-unknown-source to go on",
              file=sys.stderr)
        return 1

    net = dlibnet.load(args.dat)
    print(dlibnet.describe(net))

    model = convert(net, args.precision, source_sha256)
    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    model.save(args.out)
    weights = os.path.join(args.out, "Data", "com.apple.CoreML", "weights", "weight.bin")
    if os.path.exists(weights):
        print(f"wrote {args.out}\n  weight.bin {os.path.getsize(weights):,} bytes sha256 {sha256_of(weights)}")
    else:
        print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
