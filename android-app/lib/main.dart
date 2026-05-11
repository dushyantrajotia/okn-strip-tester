import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:web_socket_channel/io.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const OknStripApp());
}

class EyeGazeTracker {
  CameraController? _camera;
  late FaceMeshDetector _meshDetector;
  bool _isProcessing = false;
  bool _isTracking = false;
  Offset? _lastGazePoint;
  int _stableFrames = 0;
  final int _stabilityThreshold = 8;
  final double _gazeMovementThreshold = 14.0;
  final Function(String) onMovementDetected;

  EyeGazeTracker({required this.onMovementDetected}) {
    _meshDetector = FaceMeshDetector(
      option: FaceMeshDetectorOptions.faceMesh,
    );
  }

  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final frontCamera = cameras
          .firstWhere((c) => c.lensDirection == CameraLensDirection.front);
      _camera = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await _camera!.initialize();
    } catch (e) {
      print('Eye tracker init error: $e');
    }
  }

  Future<void> startTracking() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    _isTracking = true;
    _lastGazePoint = null;
    _stableFrames = 0;
    _processCameraFrames();
  }

  void stopTracking() {
    _isTracking = false;
  }

  Offset? _contourCenter(List<FaceMeshPoint>? points) {
    if (points == null || points.isEmpty) {
      return null;
    }

    var sumX = 0.0;
    var sumY = 0.0;
    for (final point in points) {
      sumX += point.x;
      sumY += point.y;
    }

    return Offset(sumX / points.length, sumY / points.length);
  }

  void _processCameraFrames() async {
    if (!_isTracking || _isProcessing) return;
    _isProcessing = true;

    try {
      final image = await _camera!.takePicture();
      final inputImage = InputImage.fromFile(File(image.path));
      final meshes = await _meshDetector.processImage(inputImage);

      if (meshes.isNotEmpty) {
        final mesh = meshes.first;
        final leftEye =
            _contourCenter(mesh.contours[FaceMeshContourType.leftEye]);
        final rightEye =
            _contourCenter(mesh.contours[FaceMeshContourType.rightEye]);
        final faceOval =
            _contourCenter(mesh.contours[FaceMeshContourType.faceOval]);

        final gazePoint = leftEye != null && rightEye != null
            ? Offset(
                (leftEye.dx + rightEye.dx) / 2, (leftEye.dy + rightEye.dy) / 2)
            : faceOval ?? mesh.boundingBox.center;

        if (_lastGazePoint == null) {
          _lastGazePoint = gazePoint;
          _stableFrames = 0;
        } else {
          final distance = (_lastGazePoint! - gazePoint).distance;

          if (distance < _gazeMovementThreshold) {
            _stableFrames++;
            if (_stableFrames < _stabilityThreshold) {
              _lastGazePoint = gazePoint;
            }
          } else {
            if (_stableFrames >= _stabilityThreshold) {
              onMovementDetected('Gaze off strip detected');
            }
            _stableFrames = 0;
            _lastGazePoint = gazePoint;
          }
        }
      }

      try {
        await File(image.path).delete();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      print('Eye tracking error: $e');
    }

    _isProcessing = false;
    if (_isTracking) {
      _processCameraFrames();
    }
  }

  Future<void> dispose() async {
    _isTracking = false;
    await _camera?.dispose();
    await _meshDetector.close();
  }
}

class OknStripApp extends StatelessWidget {
  const OknStripApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OknHomePage(),
    );
  }
}

enum EyeSide { left, right }

enum StripDirection { rtl, ltr }

const List<int> researchSpeedDegreesPerSecond = [
  20,
  30,
  40,
  50,
  60,
  70,
  80,
  90,
  100,
  160
];

class EyeParams {
  const EyeParams({
    required this.widthMm,
    required this.speedLevel,
    required this.contrastLevel,
    required this.stripColor,
    required this.bgColor,
    required this.direction,
  });

  final double widthMm;
  final int speedLevel;
  final String contrastLevel;
  final Color stripColor;
  final Color bgColor;
  final StripDirection direction;

  EyeParams copyWith({
    double? widthMm,
    int? speedLevel,
    String? contrastLevel,
    Color? stripColor,
    Color? bgColor,
    StripDirection? direction,
  }) {
    return EyeParams(
      widthMm: widthMm ?? this.widthMm,
      speedLevel: speedLevel ?? this.speedLevel,
      contrastLevel: contrastLevel ?? this.contrastLevel,
      stripColor: stripColor ?? this.stripColor,
      bgColor: bgColor ?? this.bgColor,
      direction: direction ?? this.direction,
    );
  }
}

class EyeRuntime {
  EyeRuntime({required this.params});

  EyeParams params;
  bool isRunning = false;
  double phasePx = 0;
}

class OknHomePage extends StatefulWidget {
  const OknHomePage({super.key});

  @override
  State<OknHomePage> createState() => _OknHomePageState();
}

class _OknHomePageState extends State<OknHomePage>
    with TickerProviderStateMixin {
  bool _useVrStereo = true;
  late EyeGazeTracker _eyeTracker;

  final EyeRuntime _leftEye = EyeRuntime(
    params: const EyeParams(
      widthMm: 11.5,
      speedLevel: 60,
      contrastLevel: 'full',
      stripColor: Color(0xFFFF0000),
      bgColor: Color(0xFF000000),
      direction: StripDirection.rtl,
    ),
  );

  final EyeRuntime _rightEye = EyeRuntime(
    params: const EyeParams(
      widthMm: 11.5,
      speedLevel: 60,
      contrastLevel: 'full',
      stripColor: Color(0xFFFF0000),
      bgColor: Color(0xFF000000),
      direction: StripDirection.rtl,
    ),
  );

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  IOWebSocketChannel? _channel;
  bool _isSocketConnected = false;
  String _socketUrl = 'wss://okn-controller-ws.onrender.com/ws';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame)..start();
    unawaited(_connectWebSocket());
    _eyeTracker = EyeGazeTracker(
      onMovementDetected: (message) {
        _sendSocketMessage({
          'type': 'eye-alert',
          'movement': message,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      },
    );
    unawaited(_eyeTracker.initialize());
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _channel?.sink.close();
    unawaited(_eyeTracker.dispose());
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    final dtSeconds = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;

    if (!_leftEye.isRunning && !_rightEye.isRunning) {
      return;
    }

    setState(() {
      _advanceEye(_leftEye, dtSeconds);
      _advanceEye(_rightEye, dtSeconds);
    });
  }

  Future<void> _connectWebSocket() async {
    try {
      _channel?.sink.close();
      final channel = IOWebSocketChannel.connect(Uri.parse(_socketUrl));
      _channel = channel;

      channel.stream.listen(
        _handleSocketMessage,
        onError: (_) {
          if (mounted) {
            setState(() {
              _isSocketConnected = false;
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isSocketConnected = false;
            });
          }
        },
      );

      setState(() {
        _isSocketConnected = true;
      });

      _sendSocketMessage({'type': 'identify', 'role': 'phone'});
    } catch (_) {
      setState(() {
        _isSocketConnected = false;
      });
    }
  }

  void _sendSocketMessage(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _handleSocketMessage(dynamic raw) {
    Map<String, dynamic>? msg;
    try {
      msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final action = msg['action'];
    final eyeValue = (msg['eye'] ?? 'both').toString();

    if (action == 'start') {
      _applyToEyeSelection(eyeValue, (runtime) {
        runtime.isRunning = true;
      });
      if (!_leftEye.isRunning && !_rightEye.isRunning) {
        _eyeTracker.startTracking();
      }
      _ack(eyeValue);
      return;
    }

    if (action == 'stop') {
      _applyToEyeSelection(eyeValue, (runtime) {
        runtime.isRunning = false;
        runtime.phasePx = 0;
      });
      if (!_leftEye.isRunning && !_rightEye.isRunning) {
        _eyeTracker.stopTracking();
      }
      _ack(eyeValue);
      return;
    }

    if (action == 'update') {
      final params = msg['params'];
      if (params is Map<String, dynamic>) {
        _applyToEyeSelection(eyeValue, (runtime) {
          runtime.params = _mergeParams(runtime.params, params);
        });
        _ack(eyeValue);
      }
      return;
    }

    if (action == 'vrmode') {
      final enabled = msg['enabled'];
      if (enabled is bool) {
        setState(() {
          _useVrStereo = enabled;
        });
        _ack('vr');
      }
      return;
    }
  }

  void _ack(String eye) {
    _sendSocketMessage({'status': 'ok', 'eye': eye});
  }

  EyeParams _mergeParams(EyeParams base, Map<String, dynamic> params) {
    final widthMm = (params['widthMm'] is num)
        ? (params['widthMm'] as num).toDouble()
        : base.widthMm;

    final speedValueRaw = params['speedDegPerSec'] ?? params['speedLevel'];
    final speedLevel = _normalizeSpeed(speedValueRaw, base.speedLevel);

    final contrastRaw = params['contrastLevel'];
    final contrastLevel = contrastRaw == null
        ? base.contrastLevel
        : contrastRaw.toString().toLowerCase();

    final stripColor =
        _colorFromHex(params['stripColor']?.toString()) ?? base.stripColor;
    final bgColor =
        _colorFromHex(params['bgColor']?.toString()) ?? base.bgColor;

    final direction = (params['direction']?.toString().toLowerCase() == 'ltr')
        ? StripDirection.ltr
        : StripDirection.rtl;

    return base.copyWith(
      widthMm: widthMm,
      speedLevel: speedLevel,
      contrastLevel: contrastLevel,
      stripColor: stripColor,
      bgColor: bgColor,
      direction: direction,
    );
  }

  int _normalizeSpeed(dynamic rawSpeed, int fallback) {
    if (rawSpeed is! num) {
      return fallback;
    }

    final numericSpeed = rawSpeed.round();
    if (researchSpeedDegreesPerSecond.contains(numericSpeed)) {
      return numericSpeed;
    }

    if (numericSpeed >= 1 &&
        numericSpeed <= researchSpeedDegreesPerSecond.length) {
      return researchSpeedDegreesPerSecond[numericSpeed - 1];
    }

    return fallback;
  }

  Color? _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) {
      return null;
    }
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length != 6) {
      return null;
    }
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) {
      return null;
    }
    return Color(0xFF000000 | value);
  }

  void _applyToEyeSelection(
      String eyeValue, void Function(EyeRuntime runtime) mutation) {
    setState(() {
      if (eyeValue == 'left') {
        mutation(_leftEye);
      } else if (eyeValue == 'right') {
        mutation(_rightEye);
      } else {
        mutation(_leftEye);
        mutation(_rightEye);
      }
    });
  }

  void _advanceEye(EyeRuntime runtime, double dtSeconds) {
    if (!runtime.isRunning) {
      return;
    }

    final velocity = _speedToPixelsPerSecond(runtime.params.speedLevel);
    final directionSign =
        runtime.params.direction == StripDirection.rtl ? -1.0 : 1.0;
    runtime.phasePx += velocity * directionSign * dtSeconds;

    final stripePeriod = _mmToPx(runtime.params.widthMm, _currentDpi()) * 2.0;
    if (stripePeriod <= 0) {
      runtime.phasePx = 0;
      return;
    }

    runtime.phasePx = runtime.phasePx % stripePeriod;
  }

  double _speedToPixelsPerSecond(int speedLevel) {
    const minPxPerSecond = 40.0;
    const maxPxPerSecond = 720.0;
    const minSpeedDegPerSec = 20.0;
    const maxSpeedDegPerSec = 160.0;
    final normalized = ((speedLevel - minSpeedDegPerSec) /
            (maxSpeedDegPerSec - minSpeedDegPerSec))
        .clamp(0.0, 1.0);
    return minPxPerSecond + (maxPxPerSecond - minPxPerSecond) * normalized;
  }

  double _currentDpi() {
    final mq = MediaQuery.of(context);
    return mq.devicePixelRatio * 160.0;
  }

  double _mmToPx(double mm, double dpi) {
    return (mm / 25.4) * dpi;
  }

  Future<void> _showConnectionDialog() async {
    final controller = TextEditingController(text: _socketUrl);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Set Laptop WebSocket URL',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'wss://okn-controller-ws-production.up.railway.app',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(controller.text.trim()),
                      child: const Text('Connect'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    setState(() {
      _socketUrl = result;
    });
    await _connectWebSocket();
  }

  void _showCalibrationDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final dpi = _currentDpi();
        final lineLengthPx = _mmToPx(10, dpi);
        return AlertDialog(
          scrollable: true,
          title: const Text('10mm Calibration Reference'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Place a ruler on the screen. The line below should measure exactly 10mm.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: lineLengthPx,
                    child: Container(
                      height: 3,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'If mismatch is significant, adjust by device-specific calibration factor in code.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = _currentDpi();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: VrEyeViewport(
                  eyeSide: EyeSide.left,
                  enabled: _useVrStereo,
                  child: EyePanel(
                    label: 'LEFT',
                    runtime: _leftEye,
                    dpi: dpi,
                    onStart: () {
                      setState(() {
                        _leftEye.isRunning = true;
                      });
                    },
                    onStop: () {
                      setState(() {
                        _leftEye.isRunning = false;
                        _leftEye.phasePx = 0;
                      });
                    },
                  ),
                ),
              ),
              Expanded(
                child: VrEyeViewport(
                  eyeSide: EyeSide.right,
                  enabled: _useVrStereo,
                  child: EyePanel(
                    label: 'RIGHT',
                    runtime: _rightEye,
                    dpi: dpi,
                    onStart: () {
                      setState(() {
                        _rightEye.isRunning = true;
                      });
                    },
                    onStop: () {
                      setState(() {
                        _rightEye.isRunning = false;
                        _rightEye.phasePx = 0;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Container(width: 2, color: Colors.black),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _isSocketConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        _isSocketConnected ? 'WS Connected' : 'WS Disconnected',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _miniButton('CONNECT', _showConnectionDialog),
                    const SizedBox(width: 8),
                    _miniButton(
                      _useVrStereo ? 'VR ON' : 'VR OFF',
                      () {
                        setState(() {
                          _useVrStereo = !_useVrStereo;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _miniButton('CAL', _showCalibrationDialog),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniButton(String text, VoidCallback onTap) {
    return Material(
      color: Colors.black.withOpacity(0.7),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class EyePanel extends StatelessWidget {
  const EyePanel({
    super.key,
    required this.label,
    required this.runtime,
    required this.dpi,
    required this.onStart,
    required this.onStop,
  });

  final String label;
  final EyeRuntime runtime;
  final double dpi;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: runtime.params.bgColor,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: StripedFieldPainter(
                  params: runtime.params,
                  phasePx: runtime.phasePx,
                  dpi: dpi,
                ),
              ),
            ),
          ),
          if (!runtime.isRunning)
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                ),
                onPressed: onStart,
                child: Text('START $label'),
              ),
            ),
          if (runtime.isRunning)
            Positioned(
              top: 10,
              right: 10,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white70),
                  foregroundColor: Colors.white,
                ),
                onPressed: onStop,
                child: const Text('STOP/RESET'),
              ),
            ),
        ],
      ),
    );
  }
}

class VrEyeViewport extends StatelessWidget {
  const VrEyeViewport({
    super.key,
    required this.eyeSide,
    required this.enabled,
    required this.child,
  });

  final EyeSide eyeSide;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortSide = math.min(constraints.maxWidth, constraints.maxHeight);
        final lensPadding = shortSide * 0.06;
        final tiltRadians = 6 * (math.pi / 180);
        final tilt = eyeSide == EyeSide.left ? tiltRadians : -tiltRadians;
        final alignment = eyeSide == EyeSide.left
            ? Alignment.centerRight
            : Alignment.centerLeft;

        return Container(
          color: Colors.black,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: lensPadding,
              vertical: lensPadding * 0.8,
            ),
            child: ClipOval(
              child: Transform(
                alignment: alignment,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(tilt)
                  ..scale(1.08),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: eyeSide == EyeSide.left
                                ? const Alignment(0.14, 0)
                                : const Alignment(-0.14, 0),
                            radius: 1.08,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.20),
                              Colors.black.withOpacity(0.48),
                            ],
                            stops: const [0.60, 0.82, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class StripedFieldPainter extends CustomPainter {
  const StripedFieldPainter({
    required this.params,
    required this.phasePx,
    required this.dpi,
  });

  final EyeParams params;
  final double phasePx;
  final double dpi;

  @override
  void paint(Canvas canvas, Size size) {
    final widthPx = math.max((params.widthMm / 25.4) * dpi, 1.0);

    canvas.clipRect(Offset.zero & size);

    final bgPaint = Paint()..color = params.bgColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final contrastReduction = _contrastReduction(params.contrastLevel);
    final stripColor = _blendTowardBackground(
      params.stripColor,
      params.bgColor,
      contrastReduction,
    );

    final stripePaint = Paint()..color = stripColor;
    final period = widthPx * 2;

    final normalizedPhase = phasePx % period;
    for (double x = -period + normalizedPhase;
        x < size.width + period;
        x += period) {
      canvas.drawRect(Rect.fromLTWH(x, 0, widthPx, size.height), stripePaint);
    }
  }

  double _contrastReduction(String level) {
    switch (level) {
      case '1':
        return 0.50;
      case '2':
        return 0.75;
      case '3':
        return 0.875;
      case '4':
        return 0.9375;
      case '5':
        return 0.968;
      case '6':
        return 0.9844;
      default:
        return 0.0;
    }
  }

  Color _blendTowardBackground(Color fg, Color bg, double reduction) {
    final factor = 1.0 - reduction.clamp(0.0, 1.0);

    int blend(int foreground, int background) {
      return (background + (foreground - background) * factor)
          .round()
          .clamp(0, 255);
    }

    return Color.fromARGB(
      255,
      blend(fg.red, bg.red),
      blend(fg.green, bg.green),
      blend(fg.blue, bg.blue),
    );
  }

  @override
  bool shouldRepaint(covariant StripedFieldPainter oldDelegate) {
    return oldDelegate.phasePx != phasePx ||
        oldDelegate.params != params ||
        oldDelegate.dpi != dpi;
  }
}
