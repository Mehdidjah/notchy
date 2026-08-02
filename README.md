# NotchIsland

A macOS SwiftUI app foundation for turning the MacBook notch into a dynamic,
interactive status surface.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer with Command Line Tools

## Build and run

```sh
./script/build_and_run.sh
```

Optional modes:

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

The script builds the Swift package, stages `dist/NotchIsland.app`, stops any
previous instance, and launches the new build.
