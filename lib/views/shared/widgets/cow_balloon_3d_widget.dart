import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/constants/app_constants.dart';

/// Modelo 3D interactivo de la cabeza de vaca Holstein (`medium__cow-balloon.glb`).
/// Replica la física, inclinación inicial y seguimiento del puntero de `CowBalloonModel.jsx`.
class CowBalloon3DWidget extends StatefulWidget {
  const CowBalloon3DWidget({
    super.key,
    this.pointerNormalized = Offset.zero,
    this.enableTouchDrag = true,
    this.showContactShadow = true,
  });

  /// Posición normalizada del puntero en [-1, 1] desde el centro de la ventana.
  final Offset pointerNormalized;
  final bool enableTouchDrag;
  final bool showContactShadow;

  @override
  State<CowBalloon3DWidget> createState() => _CowBalloon3DWidgetState();
}

class _CowBalloon3DWidgetState extends State<CowBalloon3DWidget>
    with SingleTickerProviderStateMixin {
  static Future<GlbCowMesh>? _cachedMeshFuture;

  late final Ticker _ticker;
  GlbCowMesh? _mesh;
  bool _loadFailed = false;

  // Rotación suavizada actual (equivale a group.current.rotation en Three.js)
  double _rotX = -0.35;
  double _rotY = 0.15;
  double _rotZ = 0.15;
  double _elapsedSeconds = 0;
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
        : ((elapsed - _lastTick).inMicroseconds / 1000000.0).clamp(0.001, 0.05);
    _lastTick = elapsed;
    _elapsedSeconds += dt;

    final Offset pointer = _touchOffset ?? widget.pointerNormalized;
    final double px = pointer.dx.clamp(-1.0, 1.0);
    final double py = pointer.dy.clamp(-1.0, 1.0);

    // Constantes equivalentes a CowBalloonModel.jsx (defaultTiltX/Y/Z + Float)
    const double defaultTiltX = -0.35;
    const double defaultTiltY = 0.15;
    const double defaultTiltZ = 0.15;

    final double floatRotX = math.sin(_elapsedSeconds * 1.4) * 0.04;
    final double floatRotY = math.cos(_elapsedSeconds * 1.1) * 0.05;

    final double targetX = (py * math.pi) / 4 + defaultTiltX + floatRotX;
    final double targetY = (px * math.pi) / 4 + defaultTiltY + floatRotY;
    final double targetZ = (px * math.pi) / 8 + defaultTiltZ;

    // Lerp independiente de tasa de cuadros (aprox 0.1 a 60Hz)
    final double alpha = 1.0 - math.pow(1.0 - 0.1, dt * 60.0).toDouble();

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
          width: 200,
          fit: BoxFit.contain,
        ),
      );
    }

    if (_mesh == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }

    final double floatYOffset = math.sin(_elapsedSeconds * 2.0) * 8.0;

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
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

/// Representación optimizada en memoria de `medium__cow-balloon.glb`.
class GlbCowMesh {
  GlbCowMesh._({
    required this.vertexCount,
    required this.triangleCount,
    required this.positions,
    required this.normals,
    required this.baseRgb,
    required this.indices,
  });

  final int vertexCount;
  final int triangleCount;
  final Float32List positions;
  final Float32List normals;
  final Uint8List baseRgb;
  final Uint32List indices;

  /// Parsea el archivo GLB v2 aplicando la matriz del nodo raíz y normalizando
  /// la escala y el centrado alrededor del origen.
  factory GlbCowMesh.fromGlbBytes(ByteData data) {
    final ByteData bytes = data;
    if (bytes.lengthInBytes < 20) {
      throw const FormatException('Archivo GLB inválido.');
    }

    final int chunk0Length = bytes.getUint32(12, Endian.little);
    final int jsonStart = 20;
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

    final int posAccIdx = attributes['POSITION'] as int;
    final int normAccIdx = attributes['NORMAL'] as int;
    final int colAccIdx = attributes['COLOR_0'] as int;
    final int idxAccIdx = primitive['indices'] as int;

    final Map<String, dynamic> posAcc =
        accessors[posAccIdx] as Map<String, dynamic>;
    final Map<String, dynamic> normAcc =
        accessors[normAccIdx] as Map<String, dynamic>;
    final Map<String, dynamic> colAcc =
        accessors[colAccIdx] as Map<String, dynamic>;
    final Map<String, dynamic> idxAcc =
        accessors[idxAccIdx] as Map<String, dynamic>;

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

    // Extraer matriz de transformación del primer nodo si existe (Z-up -> Y-up)
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
    final Uint8List rawRgb = Uint8List(vertexCount * 3);

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

      // Aplicar matriz glTF (column-major)
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

      final int cOff = colBase + i * colStride;
      final double r = bytes.getFloat32(cOff, Endian.little);
      final double g = bytes.getFloat32(cOff + 4, Endian.little);
      final double b = bytes.getFloat32(cOff + 8, Endian.little);
      rawRgb[i3] = (r.clamp(0.0, 1.0) * 255).round();
      rawRgb[i3 + 1] = (g.clamp(0.0, 1.0) * 255).round();
      rawRgb[i3 + 2] = (b.clamp(0.0, 1.0) * 255).round();
    }

    // Centrar y normalizar escala a rango [-1, 1]
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

    return _decimateForRealtime(
      vertexCount: vertexCount,
      positions: rawPos,
      normals: rawNorm,
      baseRgb: rawRgb,
      indices: rawIndices,
    );
  }

  /// Agrupa vértices cercanos en una grilla de alta resolución (128^3) para
  /// preservar el detalle anatómico de la vaca mientras garantiza renderizado fluido.
  static GlbCowMesh _decimateForRealtime({
    required int vertexCount,
    required Float32List positions,
    required Float32List normals,
    required Uint8List baseRgb,
    required Uint32List indices,
  }) {
    const int grid = 128;
    const int grid2 = grid * grid;
    final Map<int, int> cellToNewIdx = <int, int>{};
    final Int32List oldToNew = Int32List(vertexCount);

    final List<double> sumPos = <double>[];
    final List<double> sumNorm = <double>[];
    final List<double> sumCol = <double>[];
    final List<int> counts = <int>[];

    int nextIdx = 0;
    for (int i = 0; i < vertexCount; i++) {
      final int i3 = i * 3;
      final double px = positions[i3];
      final double py = positions[i3 + 1];
      final double pz = positions[i3 + 2];

      final int gx = (((px + 1.0) * 0.5) * (grid - 1)).round().clamp(0, grid - 1);
      final int gy = (((py + 1.0) * 0.5) * (grid - 1)).round().clamp(0, grid - 1);
      final int gz = (((pz + 1.0) * 0.5) * (grid - 1)).round().clamp(0, grid - 1);
      final int key = gx + gy * grid + gz * grid2;

      int? mapped = cellToNewIdx[key];
      if (mapped == null) {
        mapped = nextIdx++;
        cellToNewIdx[key] = mapped;
        sumPos.addAll(<double>[px, py, pz]);
        sumNorm.addAll(<double>[
          normals[i3],
          normals[i3 + 1],
          normals[i3 + 2],
        ]);
        sumCol.addAll(<double>[
          baseRgb[i3].toDouble(),
          baseRgb[i3 + 1].toDouble(),
          baseRgb[i3 + 2].toDouble(),
        ]);
        counts.add(1);
      } else {
        final int m3 = mapped * 3;
        sumPos[m3] += px;
        sumPos[m3 + 1] += py;
        sumPos[m3 + 2] += pz;
        sumNorm[m3] += normals[i3];
        sumNorm[m3 + 1] += normals[i3 + 1];
        sumNorm[m3 + 2] += normals[i3 + 2];
        sumCol[m3] += baseRgb[i3];
        sumCol[m3 + 1] += baseRgb[i3 + 1];
        sumCol[m3 + 2] += baseRgb[i3 + 2];
        counts[mapped] += 1;
      }
      oldToNew[i] = mapped;
    }

    final int newVertexCount = nextIdx;
    final Float32List newPos = Float32List(newVertexCount * 3);
    final Float32List newNorm = Float32List(newVertexCount * 3);
    final Uint8List newRgb = Uint8List(newVertexCount * 3);

    for (int i = 0; i < newVertexCount; i++) {
      final int c = counts[i];
      final int i3 = i * 3;
      newPos[i3] = sumPos[i3] / c;
      newPos[i3 + 1] = sumPos[i3 + 1] / c;
      newPos[i3 + 2] = sumPos[i3 + 2] / c;

      double nx = sumNorm[i3];
      double ny = sumNorm[i3 + 1];
      double nz = sumNorm[i3 + 2];
      final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 1e-6) {
        nx /= len;
        ny /= len;
        nz /= len;
      }
      newNorm[i3] = nx;
      newNorm[i3 + 1] = ny;
      newNorm[i3 + 2] = nz;

      newRgb[i3] = (sumCol[i3] / c).round().clamp(0, 255);
      newRgb[i3 + 1] = (sumCol[i3 + 1] / c).round().clamp(0, 255);
      newRgb[i3 + 2] = (sumCol[i3 + 2] / c).round().clamp(0, 255);
    }

    final List<int> keptIndices = <int>[];
    for (int i = 0; i < indices.length; i += 3) {
      final int a = oldToNew[indices[i]];
      final int b = oldToNew[indices[i + 1]];
      final int c = oldToNew[indices[i + 2]];
      if (a != b && b != c && a != c) {
        keptIndices.add(a);
        keptIndices.add(b);
        keptIndices.add(c);
      }
    }

    return GlbCowMesh._(
      vertexCount: newVertexCount,
      triangleCount: keptIndices.length ~/ 3,
      positions: newPos,
      normals: newNorm,
      baseRgb: newRgb,
      indices: Uint32List.fromList(keptIndices),
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
  });

  final GlbCowMesh mesh;
  final double rotX;
  final double rotY;
  final double rotZ;
  final double floatYOffset;
  final bool showContactShadow;

  static const int _zBuckets = 72;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final double cx = size.width * 0.5;
    final double cy = size.height * 0.46 + floatYOffset;
    final double minDim = math.min(size.width, size.height);
    final double scale = minDim * 0.44;

    // Dibujar sombra suave debajo de la cabeza de vaca
    if (showContactShadow) {
      final double shadowY = size.height * 0.46 + minDim * 0.42;
      final Rect shadowRect = Rect.fromCenter(
        center: Offset(cx, shadowY),
        width: minDim * 0.46,
        height: minDim * 0.08,
      );
      final Paint shadowPaint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFF0F172A).withValues(alpha: 0.22),
            const Color(0xFF0F172A).withValues(alpha: 0.0),
          ],
        ).createShader(shadowRect);
      canvas.drawOval(shadowRect, shadowPaint);
    }

    // Matriz Euler XYZ: R = Rx * Ry * Rz
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
    final Uint8List rgb = mesh.baseRgb;

    // Luz principal cálida (superior derecha frontal) + luz de relleno izquierda
    const double l1x = 0.56;
    const double l1y = 0.62;
    const double l1z = 0.55;

    const double l2x = -0.58;
    const double l2y = 0.42;
    const double l2z = -0.35;

    for (int i = 0; i < vCount; i++) {
      final int i3 = i * 3;
      final double px = pos[i3];
      final double py = pos[i3 + 1];
      final double pz = pos[i3 + 2];

      final double rx = m00 * px + m01 * py + m02 * pz;
      final double ry = m10 * px + m11 * py + m12 * pz;
      final double rz = m20 * px + m21 * py + m22 * pz;

      // Proyección perspectiva suave (cámara a z = 4.5)
      final double perspective = 4.5 / (4.5 - rz);
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
      final double rim = math.pow(1.0 - rnz.abs(), 2.2) * 0.14;

      final double shadeR = (0.44 + d1 * 0.68 + d2 * 0.22 + rim).clamp(0.0, 1.15);
      final double shadeG = (0.44 + d1 * 0.66 + d2 * 0.22 + rim).clamp(0.0, 1.15);
      final double shadeB = (0.46 + d1 * 0.62 + d2 * 0.25 + rim).clamp(0.0, 1.15);

      final int cr = (rgb[i3] * shadeR).round().clamp(0, 255);
      final int cg = (rgb[i3 + 1] * shadeG).round().clamp(0, 255);
      final int cb = (rgb[i3 + 2] * shadeB).round().clamp(0, 255);
      litColors[i] = (0xFF << 24) | (cr << 16) | (cg << 8) | cb;
    }

    // Back-face culling y ordenamiento por cubetas de profundidad (O(N))
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

      // En coordenadas de pantalla (Y hacia abajo), los triángulos frontales tienen cross < 0
      if (cross >= 0) {
        triBuckets[t] = -1;
        continue;
      }

      final double avgZ = (depthZ[a] + depthZ[b] + depthZ[c]) / 3.0;
      final int bucket =
          (((avgZ + 1.3) / 2.6) * (_zBuckets - 1)).round().clamp(0, _zBuckets - 1);
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

    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      triPositions,
      colors: triColors,
    );

    final Paint meshPaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = true;
    canvas.drawVertices(vertices, ui.BlendMode.modulate, meshPaint);
  }

  @override
  bool shouldRepaint(covariant _CowMeshPainter oldDelegate) {
    return oldDelegate.rotX != rotX ||
        oldDelegate.rotY != rotY ||
        oldDelegate.rotZ != rotZ ||
        oldDelegate.floatYOffset != floatYOffset ||
        oldDelegate.mesh != mesh;
  }
}
