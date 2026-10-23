# AuraFace model: source, license and inference contract

`AuraFace.mlpackage` is an original Core ML conversion of the face-recognition weight
published by **fal** in `fal/AuraFace-v1`. The model is released under Apache License
2.0. The complete accompanying license is in `AuraFace-APACHE-2.0.txt`.

| Artifact | Pinned value |
| --- | --- |
| Repository | <https://huggingface.co/fal/AuraFace-v1> |
| Revision | `af6d057c9b0ec4071d4c49c80e3539258798b609` |
| Source file | `glintr100.onnx` |
| Source size | 260,694,151 bytes |
| Source SHA-256 | `a7933ea5330113b01c9b60351d8f4c33003f145d8470ac5f0e52ee2effe25c60` |
| Source license | <https://huggingface.co/fal/AuraFace-v1/blob/af6d057c9b0ec4071d4c49c80e3539258798b609/LICENSE.md> |
| Converter | `script/face-model/convert_auraface.py` |
| Model identifier | `auraface-v1-r1` |
| Input and output | 112x112 RGB image; 512-value embedding |
| Selected precision | FP32; FP16 failed the declared synthetic parity gate |

The conversion changes the ONNX graph representation to a Core ML ML Program,
folds inference batch normalization into channel affine operations, freezes the
batch dimension to one, and supplies the RGB image normalization. An FP16 candidate
was tested separately and rejected; the selected package retains FP32 computation.
The conversion does not retrain the model.
Preserve this modification notice and the Apache license with redistributed packages.
The numerical-parity report identifies the selected artifact's exact file hashes.

## Training provenance and scope of the publisher's permission

The publisher's [model card](https://huggingface.co/fal/AuraFace-v1) describes
ResNet100 with additive angular margin loss, trained on a commercial dataset, and
its [release announcement](https://huggingface.co/blog/isidentical/auraface) explicitly
permits commercial applications. The underlying training sources are not disclosed.
This records the publisher's grant and claims; it is not an independent audit of
training-data rights or biometric performance.

Only the pinned recognition weight is converted. Other models in the source
repository are not bundled by this conversion. No InsightFace pretrained model pack
or noncommercial trained weight is downloaded as an indirect dependency.

## Inference reference attribution

The five alignment target coordinates and RGB normalization convention are documented
by the MIT-licensed **InsightFace** project, maintained by Jia Guo, Jiankang Deng and
its contributors. Notchy's converter and native inference implementation are original.
The reference source locations, pinned for review, are:

- [Five-point alignment](https://github.com/deepinsight/insightface/blob/c6c3af7bd2d0a0bf4b78c78437357f3521aa5d52/python-package/insightface/utils/face_align.py)
- [Input normalization and cosine comparison](https://github.com/deepinsight/insightface/blob/c6c3af7bd2d0a0bf4b78c78437357f3521aa5d52/python-package/insightface/model_zoo/arcface_onnx.py)
- [Source-code licensing declaration](https://github.com/deepinsight/insightface/blob/c6c3af7bd2d0a0bf4b78c78437357f3521aa5d52/README.md#license)

The reference code's MIT permission is separate from the restrictions on that
project's pretrained models. AuraFace's own Apache-2.0 grant is the permission relied
on for this weight.

## Security boundary

An identity embedding can match a printed or displayed image of the enrolled face.
This model does not establish liveness. A successful numeric conversion or a high
published face-pair accuracy is not evidence that it can safely release credentials.
Recognition thresholds and an independent passive presentation-attack detector must
pass their own validation before this candidate can enable automatic unlocking.
