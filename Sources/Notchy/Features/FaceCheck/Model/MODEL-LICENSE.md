# Face Check model: origin and licence

`FaceDescriptor.mlpackage` is a Core ML conversion of **dlib_face_recognition_resnet_model_v1**,
a face-recognition network trained and published by **Davis King**, the author of dlib
(http://dlib.net). Notchy ships it compiled as `FaceDescriptor.mlmodelc`. Face Check uses it to
tell whether the person at the camera is the one who enrolled. It turns a 150x150 aligned face
chip into a 128-number descriptor.

## Source

| | |
|---|---|
| Download | http://dlib.net/files/dlib_face_recognition_resnet_model_v1.dat.bz2 (github.com/davisking/dlib-models serves identical bytes) |
| SHA-256 of the `.bz2` | `abb1f61041e434465855ce81c2bd546e830d28bcbed8d27ffbe5bb408b11553a` |
| SHA-256 of the `.dat` | `55533b28a95800a551ba546ba62fe69625c7e95a7061c338adffead08719da30` |
| Network definition | `anet_type` in dlib's `examples/dnn_face_recognition_ex.cpp` |
| Converter | `script/face-model/convert.py` (Notchy's own code; reads the `.dat` file as data) |
| Converted weights | float16, `weight.bin` SHA-256 `20c052b69c8696378139267ec842964e19ae3fb23294ff1279c3c9265f6d27a2` |

## Licence: public domain

The dlib-models README (github.com/davisking/dlib-models, commit `fd81b63`) says:

> This repository contains trained models created by me (Davis King). They are provided as
> part of the dlib example programs, which are intended to be educational documents that
> explain how to use various parts of the dlib library. As far as I am concerned, anyone can
> do whatever they want with these model files as I've released them into the public domain.

The network definition comes from a dlib example program. Its header reads "The contents of
this file are in the public domain. See LICENSE_FOR_EXAMPLE_PROGRAMS.txt", and that file says:

> To make this as painless as possible all the example programs have been placed into the
> public domain. [...] Public domain dedications are not recognized by some countries. So if
> you live in an area where the above dedication isn't valid then you can consider the example
> programs to be licensed under the Boost Software License.

Notchy does not include or link the dlib library itself, which is under the Boost Software
License 1.0.

## Training data

The README describes the training set:

> The network was trained from scratch on a dataset of about 3 million faces. This dataset is
> derived from a number of datasets. The face scrub dataset
> (http://vintage.winklerbros.net/facescrub.html), the VGG dataset
> (http://www.robots.ox.ac.uk/~vgg/data/vgg_face/), and then a large number of images I scraped
> from the internet. [...] In the end, about half the images are from VGG and face scrub.
> Also, the total number of individual identities in the dataset is 7485. I made sure to avoid
> overlap with identities in LFW.

The source datasets have their own terms for the images. The FaceScrub site points to Creative
Commons BY-NC-ND 3.0. The VGG-Face licence file says its images are under CC BY-NC 4.0, for
non-commercial research. The model's author released the trained weights without restriction
and passes none of these terms on. Whether dataset terms bind a trained model has not been
settled in law. Notchy is free and open source. Anyone who wants to use this model
commercially should get legal advice first.

## Landmark models (not shipped)

Notchy finds faces and landmarks with Apple's Vision framework. It ships none of dlib's
landmark predictors. The two `shape_predictor_68_face_landmarks` models are trained on iBUG
300-W, and the README warns that they "can't be used in a commercial product". They must never
be bundled. `shape_predictor_5_face_landmarks` falls under the same public-domain statement and
was trained on dlib's own 5-point dataset ("7198 faces ... downloaded from the internet and
annotated with dlib's imglab tool"), but Notchy does not need it.

## Using the descriptors

dlib's convention is that two descriptors closer than 0.6 (Euclidean distance) belong to the
same person; the network was trained to put each identity inside a ball of that radius. dlib
reports 99.38% accuracy on the LFW benchmark. Face Check calibrates its own threshold and
treats a match as a convenience check, not as strong authentication.
