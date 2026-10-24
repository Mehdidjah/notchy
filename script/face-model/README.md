# Face Check model tools

AuraFace-v1 is the recognition model for guided enrollment, protected in-app checks,
and Mac Face Unlock. Its dedicated five-landmark alignment produces unmirrored
112×112 RGB inputs and 512-value, L2-normalized descriptors. See
[AURAFACE.md](AURAFACE.md) for pinned weights, conversion, preprocessing, and parity
results. The preview is mirrored only for display.

Enrollment and passive unlocking also require both MiniFASNetV2 and MiniFASNetV1SE.
They use separate 2.7× and 4× contextual crops, 80×80 BGR inputs, and independent
live-score gates. Protected in-app actions retain their prompted liveness check.

## Building the resources

Generate `Model/AuraFace.mlpackage` using the commands in the AuraFace guide. To
regenerate the two passive models, use a separate Python environment:

```sh
python3 -m venv /tmp/notchy-pad-venv
/tmp/notchy-pad-venv/bin/python -m pip install -r script/face-model/requirements-pad.txt
/tmp/notchy-pad-venv/bin/python -I script/face-model/convert_pad.py \
  --cache /tmp/notchy-pad-source \
  --out Sources/Notchy/Features/FaceCheck/Model \
  --fixture /tmp/notchy-pad-parity.json
```

`convert_pad.py` checks the architecture and checkpoint hashes at revision
`b6d5f04ad78778917853b25c778acef6d5626d15` before importing or loading them. It preserves
licenses and records conversion provenance and synthetic preprocessing/parity results.
Existing packages are protected unless `--overwrite` is explicitly supplied.

`script/build_and_run.sh` compiles these three packages into the app's Resources and
copies their license and validation files. Runtime inference is local Swift/Core ML;
the app needs no Python, ONNX, or download at launch. Release packaging requires all
three packages.

## Retired model and saved faces

The old dlib `FaceDescriptor` package, alignment implementation, and conversion tools
are no longer part of the application. Existing encrypted records are preserved.
Records containing AuraFace samples remain usable; records containing only retired
descriptors require recapture in **Settings → Face Check**. New enrollment stores
18 AuraFace samples, with no companion descriptors from the retired model.

Historical recognition comparisons can use an archived model outside the app.
The optional local test harness accepts its package path through
`NOTCHY_LEGACY_FACE_MODEL`; release builds never bundle or load it.

## Validation

Conversion parity checks numerical inference and preprocessing, not real-world
recognition or photo/video rejection. Normal builds still require a passing
`FaceModelValidation` report before automatic Mac unlocking. Removing the retired
model does not satisfy or bypass that release gate. Separate held-out camera
sessions remain necessary for calibration and attack evaluation.
