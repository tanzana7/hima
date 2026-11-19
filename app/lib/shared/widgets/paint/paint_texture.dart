import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The grayscale detail maps the paint kit can tint inside its shapes.
///
/// They are photographs, so they carry no colour of their own and no alpha
/// channel: every colour in the app still comes from `AppColors`, and where a
/// texture has to act as coverage its brightness is used instead (see
/// [paintDetailErase]).
enum PaintDetail {
  /// Long, streaky bristle marks: the inside of a loaded brush stroke.
  streak('assets/textures/paint_streak.jpg'),

  /// Broken-up strokes with holes in them: a dry brush dragging paint off.
  dryBrush('assets/textures/paint_drybrush.jpg'),

  /// Paper tooth, so a large flat fill does not read as printed.
  grain('assets/textures/paper_grain.jpg');

  const PaintDetail(this.asset);

  final String asset;
}

/// Decodes the detail maps once and shares them with every painter.
///
/// A `ui.Image` cannot be built synchronously, and decoding inside `paint()`
/// would stall the raster thread on every frame, so each map is decoded a single
/// time and then only handed out. Until the first decode finishes — and if an
/// asset is missing or unreadable — [image] returns null and the painters draw
/// the flat paint. A missing texture must never turn into a blank shape or an
/// error, so nothing here throws.
class PaintTextures {
  PaintTextures._();

  static final PaintTextures instance = PaintTextures._();

  /// The width the sources are decoded at.
  ///
  /// The largest source is 512px and the maps are sampled at roughly their own
  /// size on the hero, so decoding wider would only cost memory. Every map is
  /// tiled, so a smaller decode would show its repeats.
  static const int decodeWidth = 512;

  final Map<PaintDetail, ui.Image> _decoded = {};
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  Future<void>? _loading;

  /// Bumped once the maps are in memory, so a painter can rebuild with them.
  ValueListenable<int> get revision => _revision;

  ui.Image? image(PaintDetail detail) => _decoded[detail];

  bool get isReady => _decoded.length == PaintDetail.values.length;

  /// Starts the one decode pass. Safe to call from `build`: repeats do nothing.
  void preload() {
    _loading ??= _load();
  }

  Future<void> _load() async {
    var decoded = 0;
    for (final detail in PaintDetail.values) {
      final image = await _decode(detail);
      if (image == null) continue;
      _decoded[detail] = image;
      decoded++;
    }
    if (decoded > 0) _revision.value++;
  }

  Future<ui.Image?> _decode(PaintDetail detail) async {
    try {
      final data = await rootBundle.load(detail.asset);
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final codec = await descriptor.instantiateCodec(targetWidth: decodeWidth);
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return frame.image;
    } catch (_) {
      // Less texture is the whole failure mode: the flat paint is the fallback.
      return null;
    }
  }
}

/// A pass that modulates the paint already on the canvas with [detail].
///
/// [BlendMode.softLight] is the point: mid-grey is neutral for it, so a light
/// streak lifts the paint and a dark one deepens it while the fill keeps its
/// `AppColors` hue. [strength] pulls the map towards grey (how much detail is
/// allowed through), [alpha] how much of the pass lands at all, and [tile] the
/// size one copy of the map covers, which is what makes the streaks the size of
/// brush marks rather than of a photograph.
///
/// Returns null while the map is still decoding, so a caller can draw the flat
/// paint instead.
Paint? paintDetail(
  PaintDetail detail, {
  required Size tile,
  double angle = 0,
  double strength = 0.5,
  double alpha = 1,
  BlendMode blend = BlendMode.softLight,
  Offset offset = Offset.zero,
}) {
  final image = PaintTextures.instance.image(detail);
  if (image == null || tile.isEmpty) return null;
  return Paint()
    ..shader = ui.ImageShader(
      image,
      ui.TileMode.mirror,
      ui.TileMode.mirror,
      _tileMatrix(image, tile, angle, offset),
    )
    ..colorFilter = _detailFilter(strength, alpha)
    ..blendMode = blend;
}

/// A pass that erases what is already drawn by the brightness of [detail].
///
/// It is how a dry brush takes paint *off*: the maps have no alpha channel, so
/// brightness is turned into coverage and blended with [BlendMode.dstOut]. That
/// only affects the current layer, so the caller has to draw into a
/// `saveLayer`; on the root layer it would punch through the paper behind the
/// paint as well.
Paint? paintDetailErase(
  PaintDetail detail, {
  required Size tile,
  double angle = 0,
  double strength = 0.9,
  Offset offset = Offset.zero,
}) {
  final image = PaintTextures.instance.image(detail);
  if (image == null || tile.isEmpty) return null;
  final coverage = strength.clamp(0.0, 1.0);
  return Paint()
    ..shader = ui.ImageShader(
      image,
      ui.TileMode.mirror,
      ui.TileMode.mirror,
      _tileMatrix(image, tile, angle, offset),
    )
    ..colorFilter = ColorFilter.matrix(<double>[
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, //
      0.2126 * coverage, 0.7152 * coverage, 0.0722 * coverage, 0, 0,
    ])
    ..blendMode = BlendMode.dstOut;
}

ColorFilter _detailFilter(double strength, double alpha) {
  // Contrast around mid-grey: 1 lets the map through whole, 0 flattens it to
  // the neutral value softLight ignores.
  final contrast = strength.clamp(0.0, 1.0);
  final lift = 127.5 * (1 - contrast);
  return ColorFilter.matrix(<double>[
    contrast, 0, 0, 0, lift, //
    0, contrast, 0, 0, lift, //
    0, 0, contrast, 0, lift, //
    0, 0, 0, alpha.clamp(0.0, 1.0), 0,
  ]);
}

/// Maps the image's own pixels onto a [tile]-sized patch of the canvas, rotated
/// by [angle] and moved by [offset].
Float64List _tileMatrix(
  ui.Image image,
  Size tile,
  double angle,
  Offset offset,
) {
  final sx = tile.width / image.width;
  final sy = tile.height / image.height;
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  // Column-major, like every Flutter matrix: x' = m0·x + m4·y + m12.
  return Float64List(16)
    ..[0] = cos * sx
    ..[1] = sin * sx
    ..[4] = -sin * sy
    ..[5] = cos * sy
    ..[10] = 1
    ..[12] = offset.dx
    ..[13] = offset.dy
    ..[15] = 1;
}
