"""Convert the exact published AuraFace-v1 ONNX graph into a native Core ML package.

    python3 -I script/face-model/convert_auraface.py \
        --onnx /tmp/notchy-auraface/glintr100.onnx --download \
        --out /tmp/notchy-auraface/AuraFace-fp32.mlpackage --precision fp32

This deliberately accepts one checksum and six operator types rather than guessing how
an arbitrary ONNX network should be translated. ONNX is a conversion-time dependency;
the resulting package requires only Apple's Core ML runtime in the app.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

import auraface  # noqa: E402
import numpy as np  # noqa: E402
import onnx  # noqa: E402
from onnx import helper, numpy_helper  # noqa: E402


EXPECTED_OPERATORS = {
    "Conv": 103, "PRelu": 50, "BatchNormalization": 51,
    "Add": 49, "Flatten": 1, "Gemm": 1,
}


def attributes(node) -> dict:
    return {item.name: helper.get_attribute_value(item) for item in node.attribute}


def validate_graph(model) -> dict[str, np.ndarray]:
    onnx.checker.check_model(model)
    if [(item.domain, item.version) for item in model.opset_import] != [("", 11)]:
        raise ValueError("unexpected ONNX operator-set contract")
    graph = model.graph
    if dict(Counter(node.op_type for node in graph.node)) != EXPECTED_OPERATORS:
        raise ValueError("unexpected network topology")
    if len(graph.input) != 1 or len(graph.output) != 1:
        raise ValueError("expected one input and one output")
    input_value, output_value = graph.input[0], graph.output[0]
    dimensions = lambda value: tuple(d.dim_value or d.dim_param for d in value.type.tensor_type.shape.dim)
    if (input_value.name, input_value.type.tensor_type.elem_type, dimensions(input_value)) != (
        "data", onnx.TensorProto.FLOAT, ("None", 3, 112, 112)
    ):
        raise ValueError("unexpected input contract")
    if (output_value.name, output_value.type.tensor_type.elem_type, dimensions(output_value)) != (
        "1333", onnx.TensorProto.FLOAT, (1, 512)
    ):
        raise ValueError("unexpected output contract")
    weights = {value.name: numpy_helper.to_array(value).copy() for value in graph.initializer}
    if len(weights) != len(graph.initializer):
        raise ValueError("duplicate initializer")
    for name, value in weights.items():
        if value.dtype != np.float32 or not np.isfinite(value).all():
            raise ValueError(f"invalid weight tensor: {name}")
    return weights


def build_program(model, weights):
    import coremltools as ct
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.mil import types

    @mb.program(input_specs=[mb.TensorSpec(shape=(1, 3, 112, 112), dtype=types.fp32)],
                opset_version=ct.target.macOS14)
    def program(image):
        values = {"data": image}
        for index, node in enumerate(model.graph.node):
            if node.domain or len(node.output) != 1:
                raise ValueError(f"unsupported node: {node.name}")
            name = f"layer_{index:03d}_{node.op_type.lower()}"
            attrs = attributes(node)
            inputs = node.input
            x = values[inputs[0]]
            if node.op_type == "Conv":
                required = {"dilations", "group", "kernel_shape", "pads", "strides"}
                if set(attrs) != required or attrs["group"] != 1 or attrs["dilations"] != [1, 1]:
                    raise ValueError(f"unsupported convolution attributes: {attrs}")
                if len(inputs) != 3:
                    raise ValueError("expected already-folded convolution bias")
                top, left, bottom, right = attrs["pads"]
                result = mb.conv(x=x, weight=weights[inputs[1]], bias=weights[inputs[2]],
                                 strides=attrs["strides"], dilations=attrs["dilations"],
                                 groups=attrs["group"], pad_type="custom",
                                 pad=[top, bottom, left, right], name=name)
            elif node.op_type == "PRelu":
                if attrs or len(inputs) != 2:
                    raise ValueError("unexpected PReLU contract")
                result = mb.prelu(x=x, alpha=weights[inputs[1]].reshape(-1), name=name)
            elif node.op_type == "BatchNormalization":
                if set(attrs) != {"epsilon", "momentum"} or len(inputs) != 5:
                    raise ValueError("unexpected batch-normalization contract")
                gamma, beta, mean, variance = [weights[key].astype(np.float64) for key in inputs[1:]]
                scale = gamma / np.sqrt(variance + attrs["epsilon"])
                shift = beta - mean * scale
                shape = (1, scale.size) + (1,) * (x.rank - 2)
                result = mb.add(
                    x=mb.mul(x=x, y=scale.astype(np.float32).reshape(shape), name=name + "_scale"),
                    y=shift.astype(np.float32).reshape(shape), name=name)
            elif node.op_type == "Add":
                if attrs or len(inputs) != 2:
                    raise ValueError("unexpected addition contract")
                result = mb.add(x=x, y=values[inputs[1]], name=name)
            elif node.op_type == "Flatten":
                if attrs != {"axis": 1} or len(inputs) != 1:
                    raise ValueError("unexpected flatten contract")
                result = mb.reshape(x=x, shape=[1, -1], name=name)
            elif node.op_type == "Gemm":
                if attrs != {"alpha": 1.0, "beta": 1.0, "transB": 1} or len(inputs) != 3:
                    raise ValueError("unexpected dense-layer contract")
                result = mb.linear(x=x, weight=weights[inputs[1]], bias=weights[inputs[2]], name=name)
            else:
                raise ValueError(f"unsupported operator: {node.op_type}")
            values[node.output[0]] = result
        return mb.identity(x=values["1333"], name=auraface.OUTPUT_NAME)

    return program


def convert(source: Path, destination: Path, precision: str) -> dict:
    import coremltools as ct

    if destination.exists():
        raise FileExistsError(f"refusing to replace an existing package: {destination}")
    source_hash = auraface.verify_source(source)
    started = time.perf_counter()
    original = onnx.load(str(source), load_external_data=False)
    weights = validate_graph(original)
    image_input = ct.ImageType(
        name=auraface.INPUT_NAME, shape=(1, 3, 112, 112),
        scale=1.0 / 127.5, bias=[-1.0, -1.0, -1.0],
        color_layout=ct.colorlayout.RGB, channel_first=True,
    )
    converted = ct.convert(
        build_program(original, weights), convert_to="mlprogram", inputs=[image_input],
        compute_precision=ct.precision.FLOAT32 if precision == "fp32" else ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
        skip_model_load=True,
    )
    converted.author = "fal (AuraFace-v1); converted for Notchy"
    converted.license = "Apache-2.0; see AuraFace-LICENSE.md and AuraFace-APACHE-2.0.txt"
    converted.version = "1"
    converted.short_description = "AuraFace-v1: aligned 112x112 RGB face chip to a 512-value identity embedding."
    converted.input_description[auraface.INPUT_NAME] = "Unmirrored 112x112 RGB chip with five-point similarity alignment."
    converted.output_description[auraface.OUTPUT_NAME] = "512 unnormalized values; L2 normalize before cosine comparison."
    converted.user_defined_metadata.update({
        "notchy.faceModel.identifier": auraface.MODEL_IDENTIFIER,
        "notchy.faceModel.precision": precision,
        "notchy.faceModel.descriptorLength": str(auraface.DESCRIPTOR_LENGTH),
        "notchy.faceModel.sourceSHA256": source_hash,
        "notchy.faceModel.sourceFile": "glintr100.onnx",
        "notchy.faceModel.sourceRevision": auraface.REVISION,
        "notchy.faceModel.inputNormalization": "(RGB - 127.5) / 127.5",
        "notchy.faceModel.outputNormalization": "L2; cosine similarity",
        "notchy.faceModel.alignment": "five-point-112-v1",
        "notchy.faceModel.requiresCalibration": "true",
    })
    destination.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(destination))
    files = {str(path.relative_to(destination)): auraface.sha256_file(path)
             for path in sorted(destination.rglob("*")) if path.is_file()}
    return {
        "schemaVersion": 1, "modelIdentifier": auraface.MODEL_IDENTIFIER,
        "sourceRevision": auraface.REVISION, "sourceSHA256": source_hash,
        "precision": precision, "package": str(destination),
        "packageBytes": sum(path.stat().st_size for path in destination.rglob("*") if path.is_file()),
        "filesSHA256": files, "operatorCounts": EXPECTED_OPERATORS,
        "conversionSeconds": time.perf_counter() - started,
        "recognitionCalibrationValidated": False, "passivePADValidated": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--onnx", type=Path, required=True)
    parser.add_argument("--download", action="store_true", help="fetch the pinned source if absent")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--precision", choices=("fp32", "fp16"), required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.download:
        auraface.download_source(args.onnx)
    report = convert(args.onnx, args.out, args.precision)
    output = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.write_text(output)
    print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
