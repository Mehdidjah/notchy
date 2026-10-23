# AuraFace conversion and verification

`convert_auraface.py` translates one pinned, Apache-2.0 AuraFace-v1 weight into a
native Core ML ML Program. The app requires no ONNX, Python, OpenCV, or InsightFace
runtime. The existing dlib converter and model remain separate.

Create an isolated Python 3.14 environment and install
`requirements-auraface.txt`. The dependency versions match the verified local run;
`coremltools` and `protobuf` use their explicitly pinned prerelease versions.

```sh
python3 -m venv /tmp/notchy-auraface-venv
/tmp/notchy-auraface-venv/bin/python -m pip install -r script/face-model/requirements-auraface.txt

/tmp/notchy-auraface-venv/bin/python -I script/face-model/convert_auraface.py \
  --onnx /tmp/notchy-auraface/glintr100.onnx --download \
  --out /tmp/notchy-auraface/AuraFace-fp32.mlpackage --precision fp32 \
  --report /tmp/notchy-auraface/fp32-conversion.json

/tmp/notchy-auraface-venv/bin/python -I script/face-model/parity_auraface.py \
  --onnx /tmp/notchy-auraface/glintr100.onnx \
  --package /tmp/notchy-auraface/AuraFace-fp32.mlpackage --compute-units cpu \
  --report /tmp/notchy-auraface/fp32-parity.json
```

The selected artifact is **FP32**. FP16 was evaluated and failed the declared cosine
parity gate on synthetic inputs, so its speed advantage did not justify promotion.
Generate the selected app artifact in a clean checkout with:

```sh
/tmp/notchy-auraface-venv/bin/python -I script/face-model/convert_auraface.py \
  --onnx /tmp/notchy-auraface/glintr100.onnx --download \
  --out Sources/Notchy/Features/FaceCheck/Model/AuraFace.mlpackage --precision fp32 \
  --report /tmp/notchy-auraface/selected-conversion.json

/tmp/notchy-auraface-venv/bin/python -I script/face-model/parity_auraface.py \
  --onnx /tmp/notchy-auraface/glintr100.onnx \
  --package Sources/Notchy/Features/FaceCheck/Model/AuraFace.mlpackage \
  --compute-units cpu-ne --report /tmp/notchy-auraface/selected-parity.json
```

The generated package is approximately 261 MB and is not suitable for normal Git blob
storage. The source code, source checksum, complete license and conversion evidence
are small tracked artifacts; a clean checkout regenerates the package locally. The
converter refuses to overwrite any existing package. Evaluate alternate precision
only at a different output path and keep its own validation report.

## Conversion contract

The source is identified by revision, exact size, and SHA-256 in `auraface.py`. Its
graph must have exactly 103 convolutions, 50 PReLUs, 51 batch normalizations, 49 residual
additions, one flatten, and one dense layer. Unsupported source files and graph
contracts fail closed. Batch normalization is converted to inference-only channel
scale/shift operations, including the final rank-two output normalization layer.

Input `image` is an unmirrored 112x112 RGB chip, aligned by an orientation-preserving
similarity transform using eye centers, nose tip, and mouth corners. The five target
pixel coordinates are in `auraface.ALIGNMENT_TARGET`. Use bilinear sampling with black
pixels outside the source image. The Core ML image preprocessor applies
`(RGB - 127.5) / 127.5`; callers must not apply it a second time.

The native canonical warp is checked against **opencv-python-headless 4.12.0.88**,
with NumPy 2.0.2 and Python 3.9.6. The reference alignment source does not pin OpenCV;
this version is Notchy's explicit, reproducible raster contract. OpenCV 5 changed
the observed results, so an unversioned installation is not a compatible oracle.
The five target coordinates are Float32 values promoted to Double for fitting,
matching the published table. Sampling uses OpenCV 4.12's two-stage fixed-point
coordinates: independently rounded 1/1024 row and column terms followed by 1/32
bilinear fractions. Directly rounding the complete inverse coordinate to 1/32 is
not equivalent under rotation.

`AuraFaceCanonicalTests` compares all RGB bytes for nine synthetic warps, including
positive and negative half-cell ties, rotation, downscaling, black image borders,
and an independently fitted five-point similarity. The fixture generator and raw
source-pixel hash stay beside the local test fixture; the test suite is not
included in this repository. Regenerate in a separate
environment so its older NumPy requirement does not change the model converter:

```sh
/usr/bin/python3 -m venv /tmp/notchy-canonical-reference-venv
/tmp/notchy-canonical-reference-venv/bin/python -m pip install \
  numpy==2.0.2 opencv-python-headless==4.12.0.88
/tmp/notchy-canonical-reference-venv/bin/python -I \
  Tests/NotchyTests/Fixtures/generate_auraface_canonical.py
```

The byte-level oracle is [OpenCV 4.12's affine warp implementation](https://github.com/opencv/opencv/blob/4.12.0/modules/imgproc/src/imgwarp.cpp).
These synthetic warp tests check preprocessing only. Vision's anatomical landmark
quality still needs evaluation on the held-out camera sessions.

Output `descriptor` contains 512 unnormalized numbers. Reject nonfinite or zero-norm
vectors, L2 normalize them, and use an independently calibrated cosine threshold.
The model identifier is `auraface-v1-r1`. dlib vectors and distance thresholds are
incompatible, so adopting this model requires new enrollment and credential rebinding.

## What the report establishes

The harness compares original ONNX CPU inference against Core ML using twelve
deterministic, integer-exact synthetic chips: flat levels, RGB ramps, a spatial gradient,
seeded noise, checkerboard, and rings. These catch color-order, image-preprocessing,
graph-translation and numerical-precision errors. Optional `--chips` adds existing
112x112 aligned images without resizing. Crop names and images are not copied to the
report; it contains hashes and numeric errors. Optional `--fixture` writes only the
synthetic ONNX reference descriptors for native tests.

Parity requires cosine agreement of at least 0.99999 for FP32 and 0.9999 for FP16.
The report also records the maximum change in pairwise cosine scores, package-file
hashes, dependency versions, load and first-inference times, and warm p50/p95/max
latency after five warmup predictions over forty measured predictions by default.
The provisional warm-p95 budget is 200 ms. Python wrapper and image-bridging overhead
are included; the initial model-load measurement is process-cold, while persistent
compilation-cache state is uncontrolled. Unrelated machine load also affects timings.
Peak resident memory includes both the ONNX and Core ML runtime in the same process,
so it is not the app's standalone model memory cost.

**Conversion parity is not recognition or passive-liveness validation.** The report
always marks recognition calibration, passive PAD and automatic unlock validation
false. Promoting an artifact requires separate held-out genuine/impostor evaluation
at the chosen false-accept operating point, and passive presentation-attack testing.
Synthetic parity must never authorize password release.

## Recorded local result

`Model/AuraFace-VALIDATION.json` records the verified artifact and all three runs on
an Apple M3 Max with 36 GiB RAM. Selected FP32, configured for CPU plus Neural Engine,
had minimum cosine agreement 0.99999999934 across twelve synthetic inputs, 987 ms
initial model load, 35 ms first prediction, and 20.81/27.76 ms warm p50/p95 over forty
predictions. FP16's minimum cosine was 0.999780814, below its 0.9999 requirement, and
it was rejected. These are this machine's conversion/runtime results, not accuracy,
spoof-resistance or performance claims for all supported Macs.
