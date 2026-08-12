import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraPreviewPane extends StatefulWidget {
  const CameraPreviewPane({super.key});

  @override
  State<CameraPreviewPane> createState() => _CameraPreviewPaneState();
}

class _CameraPreviewPaneState extends State<CameraPreviewPane> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isReady = false;
  bool _isSwitchingCamera = false;

  @override
  void initState() {
    super.initState();
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
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
    );
  }
}
