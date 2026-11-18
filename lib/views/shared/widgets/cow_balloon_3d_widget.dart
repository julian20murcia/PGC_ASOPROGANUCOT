import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/constants/app_constants.dart';
import 'dairy_loader.dart';

/// Modelo 3D interactivo de vaca Holstein (`spot_holstein_cow.glb`).
/// Malla adaptativa con colores horneados de alta nitidez y seguimiento
/// suavizado al puntero del mouse o arrastre táctil.
class CowBalloon3DWidget extends StatefulWidget {
  const CowBalloon3DWidget({
    super.key,
    this.pointerNormalized = Offset.zero,
    this.enableTouchDrag = true,
    this.showContactShadow = true,
    this.scaleFactor = 0.40,
  });

  /// Posición normalizada del puntero en [-1, 1] desde el centro del área visual.
  final Offset pointerNormalized;
  final bool enableTouchDrag;
  final bool showContactShadow;
  final double scaleFactor;

  @override
  State<CowBalloon3DWidget> createState() => _CowBalloon3DWidgetState();
}

class _CowBalloon3DWidgetState extends State<CowBalloon3DWidget>
    with SingleTickerProviderStateMixin {
  static Future<GlbCowMesh>? _cachedMeshFuture;

  late final Ticker _ticker;
  GlbCowMesh? _mesh;
  bool _loadFailed = false;

  double _rotX = 0.04;
  double _rotY = 0.0;
  double _rotZ = 0.0;
  Duration _lastTick = Duration.zero;
  Offset? _touchOffset;

  @override
  void initState() {
    super.initState();
    _loadMesh();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadMesh() async {
    try {
      _cachedMeshFuture ??= rootBundle
          .load(AppConstants.cowModelAssetPath)
          .then((ByteData data) => GlbCowMesh.fromGlbBytes(data));
      final GlbCowMesh loaded = await _cachedMeshFuture!;
      if (!mounted) return;
      setState(() {
        _mesh = loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
      });
    }
  }

  void _onTick(Duration elapsed) {
    final double dt = _lastTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1000000.0)
            .clamp(0.001, 0.05);
    _lastTick = elapsed;

    final Offset pointer = _touchOffset ?? widget.pointerNormalized;
    final double px = pointer.dx.clamp(-1.0, 1.0);
    final double py = pointer.dy.clamp(-1.0, 1.0);

    const double defaultTiltX = 0.04;
    const double defaultTiltY = 0.0;
    const double defaultTiltZ = 0.0;

    final double targetX = (py * math.pi) / 9 + defaultTiltX;
    final double targetY = (px * math.pi) / 3.8 + defaultTiltY;
    final double targetZ = (px * math.pi) / 28 + defaultTiltZ;

    if ((_rotX - targetX).abs() <= 0.0005 &&
        (_rotY - targetY).abs() <= 0.0005 &&
        (_rotZ - targetZ).abs() <= 0.0005) {
      return;
    }

    final double alpha = 1.0 - math.pow(1.0 - 0.14, dt * 60.0).toDouble();

    setState(() {
      _rotX += (targetX - _rotX) * alpha;
      _rotY += (targetY - _rotY) * alpha;
      _rotZ += (targetZ - _rotZ) * alpha;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return Center(
        child: Image.asset(
          AppConstants.logoAssetPath,
          width: 160,
          fit: BoxFit.contain,
        ),
      );
    }

    if (_mesh == null) {
      return const Center(
        child: DairyLoader(
          size: DairyLoaderSize.sm,
          label: null,
        ),
      );
    }

    const double floatYOffset = 0.0;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: widget.enableTouchDrag
              ? (DragUpdateDetails details) {
                  final double hw =
                      math.max(1, constraints.maxWidth / 2).toDouble();
                  final double hh =
                      math.max(1, constraints.maxHeight / 2).toDouble();
                  setState(() {
                    _touchOffset = Offset(
                      ((details.localPosition.dx - hw) / hw).clamp(-1.0, 1.0),
                      ((details.localPosition.dy - hh) / hh).clamp(-1.0, 1.0),
                    );
                  });
                }
              : null,
          onPanEnd: widget.enableTouchDrag
              ? (_) {
                  setState(() {
                    _touchOffset = null;
                  });
                }
              : null,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _CowMeshPainter(
                mesh: _mesh!,
                rotX: _rotX,
                rotY: _rotY,
                rotZ: _rotZ,
                floatYOffset: floatYOffset,
                showContactShadow: widget.showContactShadow,
                scaleFactor: widget.scaleFactor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

/// Representación en memoria de `spot_holstein_cow.glb` con colores e iluminación horneados.
class GlbCowMesh {
  GlbCowMesh._({
    required this.vertexCount,
    required this.triangleCount,
    required this.positions,
    required this.normals,
    required this.linearRgb,
    required this.indices,
  });

  final int vertexCount;
  final int triangleCount;
  final Float32List positions;
  final Float32List normals;
  final Float32List linearRgb;
  final Uint32List indices;

  factory GlbCowMesh.fromGlbBytes(ByteData data) {
    final ByteData bytes = data;
    if (bytes.lengthInBytes < 20) {
      throw const FormatException('Archivo GLB inválido.');
    }

    final int chunk0Length = bytes.getUint32(12, Endian.little);
    const int jsonStart = 20;
    final Uint8List jsonBytes = bytes.buffer.asUint8List(
      bytes.offsetInBytes + jsonStart,
      chunk0Length,
    );
    final Map<String, dynamic> gltf =
        jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;

    final int chunk1HeaderOffset = jsonStart + chunk0Length;
    final int binStart = chunk1HeaderOffset + 8;

    final List<dynamic> bufferViews = gltf['bufferViews'] as List<dynamic>;
    final List<dynamic> accessors = gltf['accessors'] as List<dynamic>;
    final List<dynamic> meshes = gltf['meshes'] as List<dynamic>;
    final Map<String, dynamic> primitive =
        ((meshes.first as Map<String, dynamic>)['primitives'] as List<dynamic>)
            .first as Map<String, dynamic>;
    final Map<String, dynamic> attributes =
        primitive['attributes'] as Map<String, dynamic>;

    final Map<String, dynamic> posAcc =
        accessors[attributes['POSITION'] as int] as Map<String, dynamic>;
    final Map<String, dynamic> normAcc =
        accessors[attributes['NORMAL'] as int] as Map<String, dynamic>;
    final Map<String, dynamic> colAcc =
        accessors[attributes['COLOR_0'] as int] as Map<String, dynamic>;
    final Map<String, dynamic> idxAcc =
        accessors[primitive['indices'] as int] as Map<String, dynamic>;

    final int vertexCount = posAcc['count'] as int;
    final int indexCount = idxAcc['count'] as int;

    int accessorByteOffset(Map<String, dynamic> acc) {
      final Map<String, dynamic> bv =
          bufferViews[acc['bufferView'] as int] as Map<String, dynamic>;
      return binStart +
          ((bv['byteOffset'] as int?) ?? 0) +
          ((acc['byteOffset'] as int?) ?? 0);
    }

    int accessorStride(Map<String, dynamic> acc, int defaultStride) {
      final Map<String, dynamic> bv =
          bufferViews[acc['bufferView'] as int] as Map<String, dynamic>;
      return (bv['byteStride'] as int?) ?? defaultStride;
    }

    List<double> nodeMatrix = <double>[
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ];
    final List<dynamic>? nodes = gltf['nodes'] as List<dynamic>?;
    if (nodes != null && nodes.isNotEmpty) {
      final Map<String, dynamic> rootNode = nodes.first as Map<String, dynamic>;
      final List<dynamic>? m = rootNode['matrix'] as List<dynamic>?;
      if (m != null && m.length == 16) {
        nodeMatrix = m.map((dynamic e) => (e as num).toDouble()).toList();
      }
    }

    final int posBase = accessorByteOffset(posAcc);
    final int posStride = accessorStride(posAcc, 12);
    final int normBase = accessorByteOffset(normAcc);
    final int normStride = accessorStride(normAcc, 12);
    final int colBase = accessorByteOffset(colAcc);
    final int colStride = accessorStride(colAcc, 16);
    final int idxBase = accessorByteOffset(idxAcc);
    final int idxComponentType = idxAcc['componentType'] as int;

    final Float32List rawPos = Float32List(vertexCount * 3);
    final Float32List rawNorm = Float32List(vertexCount * 3);
    final Float32List rawColor = Float32List(vertexCount * 3);

    double minX = double.infinity;
    double minY = double.infinity;
    double minZ = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    double maxZ = -double.infinity;

    for (int i = 0; i < vertexCount; i++) {
      final int pOff = posBase + i * posStride;
      final double x = bytes.getFloat32(pOff, Endian.little);
      final double y = bytes.getFloat32(pOff + 4, Endian.little);
      final double z = bytes.getFloat32(pOff + 8, Endian.little);

      final double tx = nodeMatrix[0] * x +
          nodeMatrix[4] * y +
          nodeMatrix[8] * z +
          nodeMatrix[12];
      final double ty = nodeMatrix[1] * x +
          nodeMatrix[5] * y +
          nodeMatrix[9] * z +
          nodeMatrix[13];
      final double tz = nodeMatrix[2] * x +
          nodeMatrix[6] * y +
          nodeMatrix[10] * z +
          nodeMatrix[14];

      final int i3 = i * 3;
      rawPos[i3] = tx;
      rawPos[i3 + 1] = ty;
      rawPos[i3 + 2] = tz;

      if (tx < minX) minX = tx;
      if (ty < minY) minY = ty;
      if (tz < minZ) minZ = tz;
      if (tx > maxX) maxX = tx;
      if (ty > maxY) maxY = ty;
      if (tz > maxZ) maxZ = tz;

      final int nOff = normBase + i * normStride;
      final double nx = bytes.getFloat32(nOff, Endian.little);
      final double ny = bytes.getFloat32(nOff + 4, Endian.little);
      final double nz = bytes.getFloat32(nOff + 8, Endian.little);

      double tnx =
          nodeMatrix[0] * nx + nodeMatrix[4] * ny + nodeMatrix[8] * nz;
      double tny =
          nodeMatrix[1] * nx + nodeMatrix[5] * ny + nodeMatrix[9] * nz;
      double tnz =
          nodeMatrix[2] * nx + nodeMatrix[6] * ny + nodeMatrix[10] * nz;
      final double nLen = math.sqrt(tnx * tnx + tny * tny + tnz * tnz);
      if (nLen > 1e-6) {
        tnx /= nLen;
        tny /= nLen;
        tnz /= nLen;
      }
      rawNorm[i3] = tnx;
      rawNorm[i3 + 1] = tny;
      rawNorm[i3 + 2] = tnz;

      // Conversión suave lineal -> perceptual sRGB para conservar contraste nítido.
      final int cOff = colBase + i * colStride;
      final double r = bytes.getFloat32(cOff, Endian.little).clamp(0.0, 1.0);
      final double g =
          bytes.getFloat32(cOff + 4, Endian.little).clamp(0.0, 1.0);
      final double b =
          bytes.getFloat32(cOff + 8, Endian.little).clamp(0.0, 1.0);

      rawColor[i3] = math.pow(r, 1.0 / 2.2).toDouble();
      rawColor[i3 + 1] = math.pow(g, 1.0 / 2.2).toDouble();
      rawColor[i3 + 2] = math.pow(b, 1.0 / 2.2).toDouble();
    }

    final double cx = (minX + maxX) * 0.5;
    final double cy = (minY + maxY) * 0.5;
    final double cz = (minZ + maxZ) * 0.5;
    final double maxExtent = math.max(
      maxX - minX,
      math.max(maxY - minY, maxZ - minZ),
    );
    final double invScale = maxExtent > 1e-6 ? 2.0 / maxExtent : 1.0;

    for (int i = 0; i < vertexCount; i++) {
      final int i3 = i * 3;
      rawPos[i3] = (rawPos[i3] - cx) * invScale;
      rawPos[i3 + 1] = (rawPos[i3 + 1] - cy) * invScale;
      rawPos[i3 + 2] = (rawPos[i3 + 2] - cz) * invScale;
    }

    final Uint32List rawIndices = Uint32List(indexCount);
    if (idxComponentType == 5125) {
      for (int i = 0; i < indexCount; i++) {
        rawIndices[i] = bytes.getUint32(idxBase + i * 4, Endian.little);
      }
    } else if (idxComponentType == 5123) {
      for (int i = 0; i < indexCount; i++) {
        rawIndices[i] = bytes.getUint16(idxBase + i * 2, Endian.little);
      }
    }

    return GlbCowMesh._(
      vertexCount: vertexCount,
      triangleCount: indexCount ~/ 3,
      positions: rawPos,
      normals: rawNorm,
      linearRgb: rawColor,
      indices: rawIndices,
    );
  }
}

class _CowMeshPainter extends CustomPainter {
  _CowMeshPainter({
    required this.mesh,
    required this.rotX,
    required this.rotY,
    required this.rotZ,
    required this.floatYOffset,
    required this.showContactShadow,
    required this.scaleFactor,
  });

  final GlbCowMesh mesh;
  final double rotX;
  final double rotY;
  final double rotZ;
  final double floatYOffset;
  final bool showContactShadow;
  final double scaleFactor;

  static const int _zBuckets = 1024;
  static const int _maxTrisPerBatch = 18000;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final double cx = size.width * 0.5;
    final double cy = size.height * 0.48 + floatYOffset;
    final double minDim = math.min(size.width, size.height);
    final double scale = minDim * scaleFactor;

    if (showContactShadow) {
      final double shadowY = size.height * 0.45 + scale * 1.15;
      final Rect shadowRect = Rect.fromCenter(
        center: Offset(cx, shadowY),
        width: scale * 1.45,
        height: scale * 0.24,
      );
      final Paint shadowPaint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFF0F172A).withValues(alpha: 0.24),
            const Color(0xFF0F172A).withValues(alpha: 0.0),
          ],
        ).createShader(shadowRect);
      canvas.drawOval(shadowRect, shadowPaint);
    }

    final double sx = math.sin(rotX);
    final double cxR = math.cos(rotX);
    final double sy = math.sin(rotY);
    final double cyR = math.cos(rotY);
    final double sz = math.sin(rotZ);
    final double czR = math.cos(rotZ);

    final double m00 = cyR * czR;
    final double m01 = -cyR * sz;
    final double m02 = sy;

    final double m10 = cxR * sz + sx * sy * czR;
    final double m11 = cxR * czR - sx * sy * sz;
    final double m12 = -sx * cyR;

    final double m20 = sx * sz - cxR * sy * czR;
    final double m21 = sx * czR + cxR * sy * sz;
    final double m22 = cxR * cyR;

    final int vCount = mesh.vertexCount;
    final Float32List screenX = Float32List(vCount);
    final Float32List screenY = Float32List(vCount);
    final Float32List depthZ = Float32List(vCount);
    final Int32List litColors = Int32List(vCount);

    final Float32List pos = mesh.positions;
    final Float32List norm = mesh.normals;
    final Float32List rgb = mesh.linearRgb;

    // Iluminación de estudio cálida equivalente a directionalLight + pointLight
    const double l1x = 0.54;
    const double l1y = 0.64;
    const double l1z = 0.55;

    const double l2x = -0.58;
    const double l2y = 0.38;
    const double l2z = -0.32;

    for (int i = 0; i < vCount; i++) {
      final int i3 = i * 3;
      final double px = pos[i3];
      final double py = pos[i3 + 1];
      final double pz = pos[i3 + 2];

      final double rx = m00 * px + m01 * py + m02 * pz;
      final double ry = m10 * px + m11 * py + m12 * pz;
      final double rz = m20 * px + m21 * py + m22 * pz;

      final double perspective = 5.0 / (5.0 - rz);
      screenX[i] = cx + rx * scale * perspective;
      screenY[i] = cy - ry * scale * perspective;
      depthZ[i] = rz;

      final double nx = norm[i3];
      final double ny = norm[i3 + 1];
      final double nz = norm[i3 + 2];

      final double rnx = m00 * nx + m01 * ny + m02 * nz;
      final double rny = m10 * nx + m11 * ny + m12 * nz;
      final double rnz = m20 * nx + m21 * ny + m22 * nz;

      final double d1 = math.max(0.0, rnx * l1x + rny * l1y + rnz * l1z);
      final double d2 = math.max(0.0, rnx * l2x + rny * l2y + rnz * l2z);
      final double omz = 1.0 - rnz.abs();
      final double rim = omz * omz * 0.24;

      final double shadeR = (0.55 + d1 * 0.62 + d2 * 0.22 + rim).clamp(0.0, 1.18);
      final double shadeG = (0.55 + d1 * 0.60 + d2 * 0.22 + rim).clamp(0.0, 1.18);
      final double shadeB = (0.57 + d1 * 0.56 + d2 * 0.26 + rim).clamp(0.0, 1.18);

      final int cr = (rgb[i3] * 255.0 * shadeR).round().clamp(0, 255);
      final int cg = (rgb[i3 + 1] * 255.0 * shadeG).round().clamp(0, 255);
      final int cb = (rgb[i3 + 2] * 255.0 * shadeB).round().clamp(0, 255);
      litColors[i] = (0xFF << 24) | (cr << 16) | (cg << 8) | cb;
    }

    final Uint32List idx = mesh.indices;
    final int triCount = mesh.triangleCount;
    final Int32List bucketCounts = Int32List(_zBuckets);
    final Int32List triBuckets = Int32List(triCount);
    int visibleTris = 0;

    for (int t = 0; t < triCount; t++) {
      final int t3 = t * 3;
      final int a = idx[t3];
      final int b = idx[t3 + 1];
      final int c = idx[t3 + 2];

      final double ax = screenX[a];
      final double ay = screenY[a];
      final double cross =
          (screenX[b] - ax) * (screenY[c] - ay) -
          (screenY[b] - ay) * (screenX[c] - ax);

      if (cross >= 0) {
        triBuckets[t] = -1;
        continue;
      }

      final double avgZ = (depthZ[a] + depthZ[b] + depthZ[c]) / 3.0;
      final int bucket =
          (((avgZ + 1.35) / 2.7) * (_zBuckets - 1)).round().clamp(0, _zBuckets - 1);
      triBuckets[t] = bucket;
      bucketCounts[bucket]++;
      visibleTris++;
    }

    if (visibleTris == 0) {
      return;
    }

    final Int32List bucketOffsets = Int32List(_zBuckets);
    int running = 0;
    for (int b = 0; b < _zBuckets; b++) {
      bucketOffsets[b] = running;
      running += bucketCounts[b];
    }

    final Float32List triPositions = Float32List(visibleTris * 6);
    final Int32List triColors = Int32List(visibleTris * 3);

    for (int t = 0; t < triCount; t++) {
      final int bucket = triBuckets[t];
      if (bucket < 0) continue;

      final int slot = bucketOffsets[bucket]++;
      final int t3 = t * 3;
      final int a = idx[t3];
      final int b = idx[t3 + 1];
      final int c = idx[t3 + 2];

      final int pOut = slot * 6;
      triPositions[pOut] = screenX[a];
      triPositions[pOut + 1] = screenY[a];
      triPositions[pOut + 2] = screenX[b];
      triPositions[pOut + 3] = screenY[b];
      triPositions[pOut + 4] = screenX[c];
      triPositions[pOut + 5] = screenY[c];

      final int cOut = slot * 3;
      triColors[cOut] = litColors[a];
      triColors[cOut + 1] = litColors[b];
      triColors[cOut + 2] = litColors[c];
    }

    final Paint meshPaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = true;

    // Emitir en lotes seguros para respetar el límite de vértices por drawVertices
    for (int startTri = 0; startTri < visibleTris; startTri += _maxTrisPerBatch) {
      final int batchTris = math.min(_maxTrisPerBatch, visibleTris - startTri);
      final int posStart = startTri * 6;
      final int colStart = startTri * 3;

      final ui.Vertices vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(
          triPositions,
          posStart,
          posStart + batchTris * 6,
        ),
        colors: Int32List.sublistView(
          triColors,
          colStart,
          colStart + batchTris * 3,
        ),
      );

      canvas.drawVertices(vertices, ui.BlendMode.modulate, meshPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CowMeshPainter oldDelegate) {
    return oldDelegate.rotX != rotX ||
        oldDelegate.rotY != rotY ||
        oldDelegate.rotZ != rotZ ||
        oldDelegate.floatYOffset != floatYOffset ||
        oldDelegate.scaleFactor != scaleFactor ||
        oldDelegate.mesh != mesh;
  }
}
