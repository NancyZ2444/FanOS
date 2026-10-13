import 'dart:io';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();
  CameraController? _cameraController;
  String? _imagePath;
  Size? _imageSize;
  bool _scanning = false;
  bool _flashEnabled = false;
  bool _cameraUnavailable = false;
  int _cameraGeneration = 0;
  int _detectedCount = 0;
  int _completedCount = 0;
  List<ScanCropRegion> _detectedRegions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (state == AppLifecycleState.inactive) {
      _cameraGeneration++;
      setState(() => _cameraController = null);
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    final generation = ++_cameraGeneration;
    CameraController? pending;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera available');
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      pending = controller;
      await controller.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraUnavailable = false;
        _flashEnabled = false;
      });
    } catch (_) {
      await pending?.dispose();
      if (!mounted || generation != _cameraGeneration) return;
      setState(() => _cameraUnavailable = true);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      showFanToast(context, '当前设备暂不支持闪光灯');
      return;
    }
    final enabled = !_flashEnabled;
    try {
      await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _flashEnabled = enabled);
    } catch (_) {
      if (!mounted) return;
      showFanToast(context, '闪光灯暂时无法使用');
    }
  }

  Future<void> _capture() async {
    if (_scanning || _cameraController?.value.isTakingPicture == true) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      if (useMockApi) {
        showFanToast(context, '当前设备无可用相机，已进入多卡演示');
        await _recognize();
      } else {
        showFanToast(context, '当前设备无可用相机，请从相册选择小卡照片');
      }
      return;
    }
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      await _setImage(file.path);
      if (!mounted) return;
      await controller.pausePreview();
      await _recognize();
    } catch (_) {
      if (!mounted) return;
      showFanToast(context, '拍摄失败，请重试或从相册上传');
    }
  }

  @override
  void dispose() {
    _cameraGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (file == null || !mounted) return;
      await _setImage(file.path);
      if (!mounted) return;
      await _cameraController?.pausePreview();
      await _recognize();
    } catch (_) {
      if (!mounted) return;
      if (useMockApi) {
        showFanToast(context, '当前设备无法调用相册，已进入演示识别');
        await _recognize();
      } else {
        showFanToast(context, '无法读取照片，请检查相册权限后重试');
      }
    }
  }

  Future<void> _setImage(String path) async {
    final image = await decodeImageFromList(await File(path).readAsBytes());
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    if (mounted) {
      setState(() {
        _imagePath = path;
        _imageSize = size;
      });
    }
  }

  Future<void> _resetPreview() async {
    setState(() {
      _imagePath = null;
      _imageSize = null;
      _detectedCount = 0;
      _completedCount = 0;
      _detectedRegions = const [];
    });
    try {
      if (_cameraController == null) {
        await _initializeCamera();
      } else {
        await _cameraController!.resumePreview();
      }
    } catch (_) {
      await _initializeCamera();
    }
  }

  Future<void> _recognize() async {
    if (_scanning) return;
    if (!useMockApi && !ref.read(sessionProvider).isLoggedIn) {
      showFanToast(context, '请先登录后扫描小卡');
      await context.push('/login');
      if (!mounted || !ref.read(sessionProvider).isLoggedIn) return;
    }
    setState(() {
      _scanning = true;
      _detectedCount = 0;
      _completedCount = 0;
      _detectedRegions = const [];
    });
    try {
      final session = await ref
          .read(scanRepositoryProvider)
          .recognize(localImagePath: _imagePath);
      if (!mounted) return;
      setState(() {
        _detectedCount = session.detectedCount;
        _completedCount = session.detectedCount;
        _detectedRegions = session.detectedCards
            .map((item) => item.cropRegion)
            .toList();
      });
      // The synchronous API has finished all regions; do not simulate AI progress.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _scanning = false);
      await context.push<void>('/scan-result', extra: session);
      if (!mounted) return;
      await _resetPreview();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _scanning = false);
      final message = error.code == 'NETWORK_ERROR'
          ? '无法连接识别服务，请确认 Fan OS API 已启动'
          : error.message;
      showFanToast(context, message);
      try {
        await _cameraController?.resumePreview();
      } catch (_) {
        await _initializeCamera();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      showFanToast(context, '识别服务暂时不可用，请稍后重试');
      try {
        await _cameraController?.resumePreview();
      } catch (_) {
        await _initializeCamera();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15130F),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '退出扫描',
                    onPressed: _scanning ? null : () => context.go('/home'),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'AI Scan',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    tooltip: '我的扫描反馈',
                    onPressed: _scanning
                        ? null
                        : () => context.push('/scan-feedback-history'),
                    icon: const Icon(
                      Icons.history_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: _flashEnabled ? '关闭闪光灯' : '打开闪光灯',
                    onPressed: _scanning ? null : _toggleFlash,
                    icon: Icon(
                      _flashEnabled
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: _flashEnabled
                          ? const Color(0xFFFFD76A)
                          : Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (context) => const Padding(
                        padding: EdgeInsets.fromLTRB(24, 8, 24, 30),
                        child: Text(
                          '系统会自动判断卡片数量。请将一张或多张小卡完整放入画面，并尽量避免重叠、反光和遮挡。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    icon: const Icon(
                      Icons.help_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _scanning
                  ? _detectedCount == 0
                        ? '正在检测画面中的小卡…'
                        : '识别完成 · 共 $_detectedCount 张小卡'
                  : '将一张或多张小卡完整放入画面',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .78),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '尽量避免重叠、反光和遮挡，识别会更准确。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .5),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _imagePath == null
                          ? _CameraSurface(
                              controller: _cameraController,
                              unavailable: _cameraUnavailable,
                            )
                          : Center(
                              child: AspectRatio(
                                aspectRatio: _imageSize!.aspectRatio,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(
                                      File(_imagePath!),
                                      fit: BoxFit.contain,
                                    ),
                                    if (_detectedRegions.isNotEmpty)
                                      _DetectionOverlay(
                                        regions: _detectedRegions,
                                        completedCount: _completedCount,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    if (_detectedRegions.isEmpty)
                      _MultiCardGuide(scanning: _scanning)
                    else if (_imagePath == null)
                      _DetectionOverlay(
                        regions: _detectedRegions,
                        completedCount: _completedCount,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundAction(
                    icon: Icons.photo_library_outlined,
                    label: '相册',
                    onTap: _scanning ? null : () => _pick(ImageSource.gallery),
                  ),
                  GestureDetector(
                    onTap: _scanning ? null : _capture,
                    child: Container(
                      width: 74,
                      height: 74,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _scanning
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  color: FanColors.ink,
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  _RoundAction(
                    icon: useMockApi
                        ? Icons.auto_awesome_rounded
                        : Icons.refresh_rounded,
                    label: useMockApi ? '多卡演示' : '重新取景',
                    onTap: _scanning
                        ? null
                        : (useMockApi ? _recognize : _resetPreview),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface({required this.controller, required this.unavailable});

  final CameraController? controller;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller?.value.previewSize;
    if (controller != null &&
        controller!.value.isInitialized &&
        previewSize != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller!, key: const Key('camera-preview')),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const FanArtwork(
          startColor: Color(0xFF5A4F43),
          endColor: Color(0xFF191711),
          label: 'CARD',
          aspectRatio: .7,
          borderRadius: 24,
        ),
        if (!unavailable)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (unavailable)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                useMockApi ? '当前设备使用演示画面' : '相机不可用，请从相册选择照片',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }
}

class _MultiCardGuide extends StatelessWidget {
  const _MultiCardGuide({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 34, 22, 34),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: .9),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: FanColors.lavender.withValues(alpha: .3),
                blurRadius: 18,
              ),
            ],
          ),
          child: scanning
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Center(
                  child: Icon(
                    Icons.grid_view_rounded,
                    size: 34,
                    color: Colors.white.withValues(alpha: .62),
                  ),
                ),
        ),
      ),
    );
  }
}

class _DetectionOverlay extends StatelessWidget {
  const _DetectionOverlay({
    required this.regions,
    required this.completedCount,
  });

  final List<ScanCropRegion> regions;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            for (var index = 0; index < regions.length; index++)
              Positioned(
                left: regions[index].x * constraints.maxWidth,
                top: regions[index].y * constraints.maxHeight,
                width: regions[index].width * constraints.maxWidth,
                height: regions[index].height * constraints.maxHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: index < completedCount
                          ? const Color(0xFF74E0AE)
                          : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 26,
                      height: 26,
                      margin: const EdgeInsets.all(6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < completedCount
                            ? FanColors.mint
                            : Colors.black.withValues(alpha: .5),
                      ),
                      child: index < completedCount
                          ? const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: Colors.white,
                            )
                          : SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                color: Colors.white.withValues(alpha: .9),
                                strokeWidth: 1.8,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
