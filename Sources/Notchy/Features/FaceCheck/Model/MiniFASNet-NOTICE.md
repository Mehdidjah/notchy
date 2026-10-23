# MiniFASNet presentation-attack models

Copyright 2020 Minivision. The upstream repository publishes Apache License 2.0;
the accompanying `MiniFASNet-LICENSE.txt` reproduces that license.

Source: <https://github.com/minivision-ai/Silent-Face-Anti-Spoofing>
Pinned commit: `b6d5f04ad78778917853b25c778acef6d5626d15`.

The included MiniFASNetV2 and MiniFASNetV1SE packages are converted from the
official `2.7_80x80_MiniFASNetV2.pth` and `4_0_0_80x80_MiniFASNetV1SE.pth`
checkpoints. Conversion changes the runtime representation to an FP32 Core ML
program. It does not retrain or modify learned weights. Exact source and output
hashes, preprocessing, tool versions and synthetic parity results are recorded
in `MiniFASNet-manifest.json`. Reproduce with `script/face-model/convert_pad.py`.

The checkpoint files are included in the upstream repository with its root
Apache-2.0 license and no model-specific exception found in the pinned tree.
The publisher does not document training-data provenance or provide a separate
checkpoint-specific redistribution statement there. This note records the
published evidence; it is not a representation of additional publisher permission.

These RGB models estimate presentation-attack evidence. Their scores are not
authentication guarantees, and several correlated frames do not multiply the
confidence of an authentication decision. Upstream warns that results depend
on camera/scene and expects a complete face with rotation/pitch below 30 degrees.
Synthetic conversion parity is not validation against printed photos, screens,
replayed video, masks, camera injection or an actual Mac unlock.
