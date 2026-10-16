"""Read dlib's face-recognition ResNet file and run it with numpy.

The file is ``dlib_face_recognition_resnet_model_v1.dat`` (public domain, by Davis King).
dlib does not store a layer graph. It writes a network by walking the C++ template type:
each wrapper writes its version number, then the network below it, then its own record.
So the reader must already know the network's shape; ``FORWARD_LAYOUT`` spells it out in
forward order (input side first) and the reader checks every record it meets against it.

Everything here is plain Python and numpy, so it is safe to run on an untrusted download:
the file is only ever parsed as data.
"""

from __future__ import annotations

import io
from dataclasses import dataclass, field

import numpy as np

CHIP_SIZE = 150
DESCRIPTOR_LENGTH = 128

# ---------------------------------------------------------------------------------------
# Network layout, forward order.
#
# Each entry is a tuple whose first item is the kind. Tags mark a point whose output a later
# "skip" or "add_prev" refers back to; tag numbers are reused, so a reference always means
# the closest earlier tag with that number.


def _conv_block(width: int, first_stride: int) -> list[tuple]:
    return [
        ("con", width, 3, 3, first_stride),
        ("affine",),
        ("relu",),
        ("con", width, 3, 3, 1),
        ("affine",),
    ]


def _residual(width: int) -> list[tuple]:
    # relu(x + block(x))
    return [("tag", 1), *_conv_block(width, 1), ("add_prev", 1), ("relu",)]


def _residual_down(width: int) -> list[tuple]:
    # relu(avg_pool_2x2(x) + block_stride2(x)); the two sides can differ in size, and dlib
    # adds them as if the smaller one were padded with zeros at the end of each axis.
    return [
        ("tag", 1),
        *_conv_block(width, 2),
        ("tag", 2),
        ("skip", 1),
        ("avg_pool", 2, 2, 2),
        ("add_prev", 2),
        ("relu",),
    ]


FORWARD_LAYOUT: list[tuple] = [
    ("con", 32, 7, 7, 2),
    ("affine",),
    ("relu",),
    ("max_pool", 3, 3, 2),
    *_residual(32), *_residual(32), *_residual(32),
    *_residual_down(64), *_residual(64), *_residual(64), *_residual(64),
    *_residual_down(128), *_residual(128), *_residual(128),
    *_residual_down(256), *_residual(256), *_residual(256),
    *_residual_down(256),
    ("avg_pool", 0, 0, 1),  # window 0 means "the whole plane"
    ("fc_no_bias", DESCRIPTOR_LENGTH),
]


# ---------------------------------------------------------------------------------------
# Parsed layers


@dataclass
class InputLayer:
    channel_means: np.ndarray  # red, green, blue, in 0-255 units
    size: tuple[int, int]


@dataclass
class Conv:
    weight: np.ndarray  # (out, in, rows, cols)
    bias: np.ndarray | None
    stride: tuple[int, int]
    padding: tuple[int, int]
    fused_relu: bool = False


@dataclass
class Affine:
    scale: np.ndarray  # per channel
    shift: np.ndarray


@dataclass
class Relu:
    pass


@dataclass
class Pool:
    kind: str  # "max" or "avg"
    window: tuple[int, int]  # (0, 0) = whole plane
    stride: tuple[int, int]
    padding: tuple[int, int]


@dataclass
class Tag:
    number: int


@dataclass
class Skip:
    number: int


@dataclass
class AddPrev:
    number: int


@dataclass
class Dense:
    weight: np.ndarray  # (inputs, outputs)
    bias: np.ndarray | None


@dataclass
class FaceNet:
    input: InputLayer
    layers: list = field(default_factory=list)
    loss_margin: float = 0.0
    loss_distance_threshold: float = 0.0

    def parameter_count(self) -> int:
        total = 0
        for layer in self.layers:
            if isinstance(layer, (Conv, Dense)):
                total += layer.weight.size + (0 if layer.bias is None else layer.bias.size)
            elif isinstance(layer, Affine):
                total += layer.scale.size + layer.shift.size
        return total


class FormatError(ValueError):
    pass


# ---------------------------------------------------------------------------------------
# Primitive decoding


class _Stream:
    def __init__(self, data: bytes):
        self._buffer = io.BytesIO(data)
        self._size = len(data)

    def position(self) -> int:
        return self._buffer.tell()

    def remaining(self) -> int:
        return self._size - self._buffer.tell()

    def take(self, count: int) -> bytes:
        chunk = self._buffer.read(count)
        if len(chunk) != count:
            raise FormatError(f"file ends early at byte {self.position()}")
        return chunk

    def integer(self) -> int:
        # One control byte: low nibble = byte count, bit 7 = negative. Then the magnitude,
        # least significant byte first.
        control = self.take(1)[0]
        if control & 0x70:
            raise FormatError(f"bad integer control byte 0x{control:02x} at {self.position() - 1}")
        count = control & 0x0F
        if count == 0 or count > 8:
            raise FormatError(f"bad integer length {count} at {self.position() - 1}")
        magnitude = int.from_bytes(self.take(count), "little")
        return -magnitude if control & 0x80 else magnitude

    def real(self) -> float:
        # Stored as an integer mantissa and an integer power of two.
        mantissa = self.integer()
        exponent = self.integer()
        if exponent == 32000:
            return float("inf")
        if exponent == 32001:
            return float("-inf")
        if exponent == 32002:
            return float("nan")
        return float(np.ldexp(np.float64(mantissa), exponent))

    def boolean(self) -> bool:
        value = self.take(1)
        if value == b"1":
            return True
        if value == b"0":
            return False
        raise FormatError(f"bad boolean {value!r} at {self.position() - 1}")

    def text(self) -> str:
        length = self.integer()
        if length < 0 or length > 4096:
            raise FormatError(f"implausible string length {length}")
        return self.take(length).decode("ascii")

    def expect_text(self, *allowed: str) -> str:
        found = self.text()
        if found not in allowed:
            raise FormatError(f"expected one of {allowed}, found {found!r} at {self.position()}")
        return found

    def tensor(self) -> np.ndarray:
        version = self.integer()
        if version != 2:
            raise FormatError(f"unsupported tensor version {version}")
        shape = tuple(self.integer() for _ in range(4))
        if any(d < 0 for d in shape):
            raise FormatError(f"negative tensor shape {shape}")
        count = int(np.prod(shape, dtype=np.int64))
        if count * 4 > self.remaining():
            raise FormatError(f"tensor of {count} floats does not fit in the file")
        values = np.frombuffer(self.take(count * 4), dtype="<f4").astype(np.float32)
        return values.reshape(shape)

    def tensor_view(self) -> tuple[int, int, int, int]:
        version = self.integer()
        if version != 1:
            raise FormatError(f"unsupported tensor view version {version}")
        return tuple(self.integer() for _ in range(4))


# ---------------------------------------------------------------------------------------
# Layer records


def _read_input(stream: _Stream) -> InputLayer:
    stream.expect_text("input_rgb_image_sized")
    means = np.array([stream.real(), stream.real(), stream.real()], dtype=np.float64)
    rows, cols = stream.integer(), stream.integer()
    if (rows, cols) != (CHIP_SIZE, CHIP_SIZE):
        raise FormatError(f"expected a {CHIP_SIZE}x{CHIP_SIZE} input, found {rows}x{cols}")
    return InputLayer(channel_means=means, size=(rows, cols))


def _read_conv(stream: _Stream, spec: tuple) -> Conv:
    _, filters, rows, cols, stride = spec
    version = stream.expect_text("con_4", "con_5", "con_6")
    params = stream.tensor().reshape(-1)
    found_filters = stream.integer()
    found_rows, found_cols = stream.integer(), stream.integer()
    stride_y, stride_x = stream.integer(), stream.integer()
    pad_y, pad_x = stream.integer(), stream.integer()
    weight_view = stream.tensor_view()
    bias_view = stream.tensor_view()
    for _ in range(4):  # learning-rate and weight-decay multipliers; training only
        stream.real()
    use_bias = stream.boolean() if version in ("con_5", "con_6") else True
    fused_relu = stream.boolean() if version == "con_6" else False

    if (found_filters, found_rows, found_cols, stride_y, stride_x) != (filters, rows, cols, stride, stride):
        raise FormatError(
            f"convolution mismatch: file has {found_filters} {found_rows}x{found_cols}/{stride_y}, "
            f"layout expects {filters} {rows}x{cols}/{stride}"
        )
    if weight_view[0] != filters or weight_view[2:] != (rows, cols):
        raise FormatError(f"unexpected filter view {weight_view}")
    weight_count = int(np.prod(weight_view))
    weight = params[:weight_count].reshape(weight_view)
    bias = None
    if use_bias:
        bias_count = int(np.prod(bias_view))
        if bias_count != filters or params.size != weight_count + bias_count:
            raise FormatError("convolution parameter block has the wrong size")
        bias = params[weight_count:].copy()
    elif params.size != weight_count:
        raise FormatError("convolution parameter block has the wrong size")
    return Conv(weight=weight.copy(), bias=bias, stride=(stride_y, stride_x),
                padding=(pad_y, pad_x), fused_relu=fused_relu)


def _read_affine(stream: _Stream) -> Affine | None:
    version = stream.expect_text("affine_", "affine_2", "bn_con2")
    params = stream.tensor().reshape(-1)
    gamma_view = stream.tensor_view()
    beta_view = stream.tensor_view()
    count = int(np.prod(gamma_view))
    if int(np.prod(beta_view)) != count or params.size != 2 * count:
        raise FormatError("affine parameter block has the wrong size")
    gamma = params[:count].astype(np.float64)
    beta = params[count:].astype(np.float64)

    if version == "bn_con2":
        # A batch-norm layer saved during training: fold its running statistics in, the
        # same way dlib does when it turns one into an affine layer.
        stream.tensor()  # batch means
        stream.tensor()  # batch inverse deviations
        running_means = stream.tensor().reshape(-1).astype(np.float64)
        running_variances = stream.tensor().reshape(-1).astype(np.float64)
        stream.integer()  # update count
        stream.integer()  # running-statistics window
        for _ in range(4):
            stream.real()
        eps = stream.real()
        scale = (gamma / np.sqrt(running_variances + eps)).astype(np.float32)
        shift = (beta - scale.astype(np.float64) * running_means).astype(np.float32)
        return Affine(scale=scale, shift=shift)

    mode = stream.integer()
    disabled = stream.boolean() if version == "affine_2" else False
    if mode != 0:
        raise FormatError("expected a per-channel (convolution mode) affine layer")
    if disabled:
        return None
    return Affine(scale=gamma.astype(np.float32), shift=beta.astype(np.float32))


def _read_relu(stream: _Stream) -> Relu | None:
    version = stream.expect_text("relu_", "relu_2")
    if version == "relu_2" and stream.boolean():
        return None
    return Relu()


def _read_pool(stream: _Stream, spec: tuple) -> Pool:
    kind, rows, cols, stride = spec
    stream.expect_text(f"{kind}_2")
    found = tuple(stream.integer() for _ in range(6))
    if found[:4] != (rows, cols, stride, stride):
        raise FormatError(f"{kind} mismatch: file has {found}, layout expects {spec[1:]}")
    return Pool(kind="max" if kind == "max_pool" else "avg", window=(rows, cols),
                stride=(stride, stride), padding=(found[4], found[5]))


def _read_dense(stream: _Stream, spec: tuple) -> Dense:
    _, outputs = spec
    version = stream.expect_text("fc_2", "fc_3")
    found_outputs = stream.integer()
    inputs = stream.integer()
    params = stream.tensor().reshape(-1)
    weight_view = stream.tensor_view()
    stream.tensor_view()  # bias view, unused without a bias
    bias_mode = stream.integer()
    for _ in range(4):
        stream.real()
    if version == "fc_3":
        stream.boolean()
    if found_outputs != outputs or bias_mode != 1:
        raise FormatError(f"expected a {outputs}-output layer without bias")
    if weight_view[:2] != (inputs, outputs) or params.size != inputs * outputs:
        raise FormatError("fully connected parameter block has the wrong size")
    return Dense(weight=params.reshape(inputs, outputs).copy(), bias=None)


def _read_layer_record(stream: _Stream, spec: tuple):
    kind = spec[0]
    if kind == "con":
        return _read_conv(stream, spec)
    if kind == "affine":
        return _read_affine(stream)
    if kind == "relu":
        return _read_relu(stream)
    if kind in ("max_pool", "avg_pool"):
        return _read_pool(stream, spec)
    if kind == "add_prev":
        stream.expect_text("add_prev_")
        return AddPrev(spec[1])
    if kind == "fc_no_bias":
        return _read_dense(stream, spec)
    raise AssertionError(kind)


def _skip_runtime_state(stream: _Stream, wrapper_version: int, on_input: bool) -> None:
    # Flags and scratch tensors that dlib saves next to every layer; empty in a clean model.
    for _ in range(3):
        stream.boolean()
    stream.tensor()  # input gradient
    stream.tensor()  # cached output
    if on_input or wrapper_version >= 2:
        stream.tensor()  # parameter gradient (the final gradient on the input-side layer)
    if on_input and wrapper_version >= 3:
        stream.integer()  # sample expansion factor


def load(path: str) -> FaceNet:
    with open(path, "rb") as handle:
        return parse(handle.read())


def parse(data: bytes) -> FaceNet:
    stream = _Stream(data)

    if stream.integer() != 1:
        raise FormatError("not a dlib loss-layer network")
    loss_version = stream.expect_text("loss_metric_", "loss_metric_2")
    margin, threshold = 0.1, 0.75
    if loss_version == "loss_metric_2":
        margin, threshold = stream.real(), stream.real()

    # One version number per wrapper, outermost (last forward layer) first.
    versions: dict[int, int] = {}
    for index in range(len(FORWARD_LAYOUT) - 1, -1, -1):
        spec = FORWARD_LAYOUT[index]
        version = stream.integer()
        if spec[0] in ("tag", "skip"):
            allowed = (1,)
        else:
            allowed = (2, 3) if index == 0 else (1, 2)
        if version not in allowed:
            raise FormatError(f"wrapper for {spec} has version {version}, expected {allowed}")
        versions[index] = version

    input_layer = _read_input(stream)

    layers = []
    for index, spec in enumerate(FORWARD_LAYOUT):
        kind = spec[0]
        if kind == "tag":
            layers.append(Tag(spec[1]))
            continue
        if kind == "skip":
            layers.append(Skip(spec[1]))
            continue
        record = _read_layer_record(stream, spec)
        _skip_runtime_state(stream, versions[index], on_input=(index == 0))
        if record is not None:
            layers.append(record)

    if stream.remaining() != 0:
        raise FormatError(f"{stream.remaining()} unread bytes at the end of the file")
    return FaceNet(input=input_layer, layers=layers, loss_margin=margin,
                   loss_distance_threshold=threshold)


# ---------------------------------------------------------------------------------------
# Reference forward pass (numpy). Mirrors dlib's CPU arithmetic, so it doubles as a check
# that the layout above and the converted Core ML graph mean the same thing.


def preprocess(chip_rgb: np.ndarray, net: FaceNet, dtype=np.float64) -> np.ndarray:
    """150x150x3 uint8 RGB -> 3x150x150 tensor, (value - channel mean) / 256."""
    if chip_rgb.shape != (CHIP_SIZE, CHIP_SIZE, 3) or chip_rgb.dtype != np.uint8:
        raise ValueError("expected a 150x150x3 uint8 RGB chip")
    planes = chip_rgb.astype(dtype).transpose(2, 0, 1)
    return (planes - net.input.channel_means.astype(dtype)[:, None, None]) / dtype(256.0)


def _conv(x: np.ndarray, layer: Conv) -> np.ndarray:
    weight = layer.weight.astype(x.dtype)
    (pad_y, pad_x), (stride_y, stride_x) = layer.padding, layer.stride
    if pad_y or pad_x:
        x = np.pad(x, ((0, 0), (pad_y, pad_y), (pad_x, pad_x)))
    rows, cols = weight.shape[2:]
    windows = np.lib.stride_tricks.sliding_window_view(x, (rows, cols), axis=(1, 2))
    windows = windows[:, ::stride_y, ::stride_x]
    out = np.einsum("chwij,fcij->fhw", windows, weight, optimize=True)
    if layer.bias is not None:
        out = out + layer.bias.astype(x.dtype)[:, None, None]
    return np.maximum(out, 0) if layer.fused_relu else out


def _pool(x: np.ndarray, layer: Pool) -> np.ndarray:
    if layer.window == (0, 0):
        reduce = np.max if layer.kind == "max" else np.mean
        return reduce(x, axis=(1, 2), keepdims=True)
    if layer.padding != (0, 0):
        raise NotImplementedError("padded pooling is not used by this network")
    rows, cols = layer.window
    stride_y, stride_x = layer.stride
    windows = np.lib.stride_tricks.sliding_window_view(x, (rows, cols), axis=(1, 2))
    windows = windows[:, ::stride_y, ::stride_x]
    return windows.max(axis=(3, 4)) if layer.kind == "max" else windows.mean(axis=(3, 4))


def _padded_sum(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    shape = tuple(max(p, q) for p, q in zip(a.shape, b.shape))
    out = np.zeros(shape, dtype=a.dtype)
    out[tuple(slice(0, d) for d in a.shape)] += a
    out[tuple(slice(0, d) for d in b.shape)] += b
    return out


def forward(net: FaceNet, chip_rgb: np.ndarray, dtype=np.float64) -> np.ndarray:
    x = preprocess(chip_rgb, net, dtype)
    tagged: dict[int, np.ndarray] = {}
    for layer in net.layers:
        if isinstance(layer, Tag):
            tagged[layer.number] = x
        elif isinstance(layer, Skip):
            x = tagged[layer.number]
        elif isinstance(layer, AddPrev):
            x = _padded_sum(x, tagged[layer.number])
        elif isinstance(layer, Conv):
            x = _conv(x, layer)
        elif isinstance(layer, Affine):
            x = x * layer.scale.astype(dtype)[:, None, None] + layer.shift.astype(dtype)[:, None, None]
        elif isinstance(layer, Relu):
            x = np.maximum(x, 0)
        elif isinstance(layer, Pool):
            x = _pool(x, layer)
        elif isinstance(layer, Dense):
            x = x.reshape(-1) @ layer.weight.astype(dtype)
            if layer.bias is not None:
                x = x + layer.bias.astype(dtype)
        else:
            raise AssertionError(type(layer))
    return x.reshape(-1)


def describe(net: FaceNet) -> str:
    convs = sum(isinstance(layer, Conv) for layer in net.layers)
    return "\n".join([
        f"input {net.input.size[0]}x{net.input.size[1]} RGB, channel means "
        + ", ".join(f"{m:.6g}" for m in net.input.channel_means),
        f"loss margin {net.loss_margin:g}, distance threshold {net.loss_distance_threshold:g}",
        f"{len(net.layers)} layers, {convs} convolutions, {net.parameter_count():,} parameters",
    ])
