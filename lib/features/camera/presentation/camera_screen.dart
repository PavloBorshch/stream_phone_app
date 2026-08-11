import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const double _expansionBarHeight = 48;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isReady = false;
  bool _isSwitchingCamera = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        return;
      }

      _selectedCameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (_selectedCameraIndex == -1) {
        _selectedCameraIndex = 0;
      }

      await _initializeCamera(_selectedCameraIndex);
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  Future<void> _initializeCamera(int index) async {
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose();
      rethrow;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _isReady = true;
      _isSwitchingCamera = false;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera) {
      return;
    }

    final previousController = _controller;
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;

    setState(() {
      _isSwitchingCamera = true;
      _isReady = false;
      _controller = null;
      _selectedCameraIndex = nextIndex;
    });

    await previousController?.dispose();

    try {
      await _initializeCamera(nextIndex);
    } catch (e) {
      debugPrint('Camera switch error: $e');
      if (mounted) {
        setState(() => _isSwitchingCamera = false);
      }
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          const _ExpansionLimitBar(isTop: true),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_isReady && _controller != null && _controller!.value.isInitialized)
                  CameraPreview(
                    _controller!,
                    key: ValueKey(_selectedCameraIndex),
                  ),
                if (!_isReady || _isSwitchingCamera)
                  const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.redAccent),
                    ),
                  ),
                SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 8,
                        left: 16,
                        right: 16,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'FPS: 60 | 0 kbps',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                              onPressed: () {
                                debugPrint('Open settings');
                              },
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              debugPrint('Start stream');
                            },
                            child: Container(
                              height: 70,
                              width: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                color: Colors.redAccent,
                              ),
                              child: const Icon(
                                Icons.videocam,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: IconButton(
                          onPressed: _cameras.length < 2 || _isSwitchingCamera ? null : _switchCamera,
                          icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 32),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _ExpansionLimitBar(isTop: false),
        ],
      ),
    );
  }
}

class _ExpansionLimitBar extends StatelessWidget {
  const _ExpansionLimitBar({required this.isTop});

  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _CameraScreenState._expansionBarHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: isTop ? const BorderSide(color: Colors.white24) : BorderSide.none,
          top: isTop ? BorderSide.none : const BorderSide(color: Colors.white24),
        ),
      ),
    );
  }
}
