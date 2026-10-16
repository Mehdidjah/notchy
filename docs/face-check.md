# Face Check

Face Check authorizes actions inside Notchy. It never unlocks the operating
system or stores a login password. Only encrypted face descriptors are saved;
camera images and liveness measurements remain in memory. Clipboard storage
retains its existing format; the hidden-item feature gates presentation and export.

## Flow

1. Open the Face tab and choose **Scan my face**. Camera permission is required.
2. Look straight at the camera, blink, turn toward the requested shoulder, and
   look back. Then capture the nine enrollment poses. **Finish now** needs a
   current live check and at least a straight-on sample.
3. Successful persistence plays **Face saved**. Later, **Check now**, revealing a
   hidden item, or confirming a protected action starts a fresh check.
4. The pill begins unfolding after 160 ms, with a 450 ms spring. A bold blue
   face breathes while scanning. On a result, its corners close into a circle,
   three rings rotate, then a check draws from 0.8–1.18 seconds. Failure returns
   to a dimmed blue face with a short shake. Success holds for 1.7 seconds;
   failure holds for five seconds. Hovering over failure starts a new challenge;
   the close button or Escape ends the request. Reduce Motion uses stable states.
5. A check times out after ten seconds even if no frames arrive. Failed or
   cancelled checks never release the pending action. A compact window keeps
   prompts visible when the notch is disabled or hidden in fullscreen.

Sensitive clips have per-item, in-memory grants lasting 60 seconds. Search,
previews, metadata, accessibility labels, menus and exports are redacted or gated.
Expiration is checked at use time. Item replacement/deletion invalidates a pending
approval. App deactivation hides revealed content; session deactivation and sleep
also cancel pending checks. Clear history always requests fresh authorization
when enrollment exists. With no enrollment it retains ordinary history clearing.

## Liveness limits and validation

Vision provides landmarks, head pose, capture quality and rectangles. Face-crop
pixel analysis measures broad connected reflections. A blink must open, close
and reopen both eyes. A requested turn must show nose motion beyond an eye/mouth
projective plane, then return to center. Missing frames, poor quality, multiple
faces and identity changes discard progress. Denial cues override a matching
descriptor. Camera-delivery timestamps precede model work; pre-challenge and
stale frames cannot contribute.

These are RGB heuristics, not measured depth. Automated fixtures reject static
and planar pictures and wrong-direction sequences; a sufficiently convincing
replay can still defeat camera heuristics. Real-camera thresholds remain
uncalibrated until the following manual checks have been completed:

- Enroll, restart Notchy, and recognize the saved face in daylight and room light.
- Verify left/right shoulder prompts and all nine grid cells with the mirrored preview.
- Check printed photos, a phone displaying a photo, and prerecorded video, both
  with and without visible device edges or glare. Record any acceptance.
- Check glasses, skin highlights and a bright window for false rejections.
- Test hidden-item reveal/expiry, clipboard copy/paste/drag, clear-history cancel,
  retry, camera denial/unavailability, and a disabled/fullscreen-hidden notch.

## Developer checks

```sh
swift test --filter 'FaceCheck|ClipboardFaceAuthorizationTests|NotchViewModelTests'
./script/build_and_run.sh --perf
NOTCHY_FACE_SNAPSHOTS=/tmp/notchy-face-snapshots swift test --filter FaceCheckPresentationTests
```

The last command optionally writes native-view PNGs for visual inspection. No
environment variables are required at runtime. The snapshots include intermediate
ring and check frames. Animation paths are drawn natively in an asynchronous
Canvas, with no video assets or frame-driven observable-model updates. The
performance command measures expansion, breathing, success, failure and retry
in addition to tab switches; its animation preview never authorizes an action.
Structured lifecycle logs use
the `com.local.Notchy` subsystem and `FaceCheck` category, without descriptors,
images or clipboard contents. Existing timing-sensitive Focus and Timer tests
may fail under the full parallel test load; repeat a reported test in isolation.
