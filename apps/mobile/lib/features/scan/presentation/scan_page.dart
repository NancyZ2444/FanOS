import 'dart:io';

import 'package:camera/camera.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/scan/presentation/scan_selection.dart';
import 'package:fan_os/features/scan/presentation/scan_original_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({this.originalLocation = true, super.key});
  final bool originalLocation;
  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _active = false, _unavailable = false, _flash = false, _busy = false;
  bool _pickingImage = false;
  CameraLensDirection _lens = CameraLensDirection.back;
  int _generation = 0, _operation = 0;
  String? _imagePath, _error;
  Size _imageSize = const Size(3, 4);
  ScanDetection? _detection;
  ScanSession? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (_active == active) return;
    _active = active;
    if (active && _imagePath == null) {
      _initializeCamera();
    } else if (!active) {
      _disposeCamera();
    }
  }

  void _disposeCamera() {
    _generation++;
    final controller = _camera;
    _camera = null;
    controller?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      setState(_disposeCamera);
    } else if (state == AppLifecycleState.resumed &&
        _active &&
        _imagePath == null &&
        _detection == null) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (!_active || !mounted) return;
    _disposeCamera();
    final generation = _generation;
    CameraController? pending;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera');
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == _lens,
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
      if (!mounted || generation != _generation || !_active) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _unavailable = false;
        _flash = false;
      });
    } catch (_) {
      await pending?.dispose();
      if (mounted && generation == _generation) {
        setState(() => _unavailable = true);
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_camera == null) {
      showFanToast(context, '当前设备暂不支持闪光灯');
      return;
    }
    try {
      await _camera!.setFlashMode(_flash ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _flash = !_flash);
    } catch (_) {
      if (mounted) showFanToast(context, '闪光灯暂时无法使用');
    }
  }

  Future<void> _capture({bool gallery = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pickingImage = gallery;
      _error = null;
    });
    try {
      String? path;
      if (gallery) {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 2400,
        );
        if (file == null) return;
        path = file.path;
      } else if (_camera?.value.isInitialized == true) {
        path = (await _camera!.takePicture()).path;
      } else if (!useMockApi) {
        if (mounted) showFanToast(context, '相机不可用，请从相册选择照片');
        return;
      }
      if (!mounted) return;
      if (path != null) {
        final decoded = await decodeImageFromList(
          await File(path).readAsBytes(),
        );
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        decoded.dispose();
      }
      if (!mounted) return;
      setState(() {
        _imagePath = path;
        _pickingImage = false;
        _detection = null;
        _lastResult = null;
        _disposeCamera();
      });
      await _detect();
    } catch (_) {
      if (mounted) {
        final message = gallery ? '无法读取照片，请检查相册权限后重试' : '拍摄失败，请重试或从相册选择';
        if (widget.originalLocation) {
          setState(() => _error = message);
        } else {
          showFanToast(context, message);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pickingImage = false;
        });
      }
    }
  }

  Future<void> _detect() async {
    if (!useMockApi && !ref.read(sessionProvider).isLoggedIn) {
      await context.push('/login');
      if (!mounted) return;
      if (!ref.read(sessionProvider).isLoggedIn) {
        setState(() => _error = '请登录后重试检测，照片已保留。');
        return;
      }
    }
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detection = await ref
          .read(scanDetectionRepositoryProvider)
          .detect(_imagePath);
      if (!mounted || operation != _operation) return;
      setState(() => _detection = detection);
    } catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _error = _message(error, detecting: true));
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
    if (widget.originalLocation &&
        mounted &&
        operation == _operation &&
        _error == null &&
        _detection!.regions.isNotEmpty) {
      await _recognize(_detection!.regions.map((r) => r.id).toSet());
    }
  }

  String _message(Object error, {bool detecting = false}) {
    if (error is ApiException) {
      return error.message;
    }
    return detecting ? '暂时无法检测小卡，请检查网络后重试。' : '暂时无法识别，已保留选中的小卡，请重试。';
  }

  Future<void> _recognize(Set<String> ids) async {
    if (_busy || ids.isEmpty || _detection == null) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(scanDetectionRepositoryProvider)
          .recognize(_detection!, ids);
      if (!mounted || operation != _operation) return;
      setState(() {
        _busy = false;
        _lastResult = result;
      });
      await context.push<void>(
        widget.originalLocation ? '/scan-original-result' : '/scan-result',
        extra: result,
      );
      if (mounted && !widget.originalLocation) _retake();
    } catch (error) {
      if (mounted && operation == _operation) {
        setState(() {
          _error = _message(error);
          _busy = false;
        });
      }
    }
  }

  void _retake() {
    _operation++;
    setState(() {
      _imagePath = null;
      _detection = null;
      _lastResult = null;
      _error = null;
      _busy = false;
    });
    _initializeCamera();
  }

  @override
  void dispose() {
    _operation++;
    _disposeCamera();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.originalLocation &&
          !_pickingImage &&
          (_imagePath != null || _detection != null || _busy || _error != null)
      ? _buildOriginalLocation(context)
      : AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: const Color(0xFF24232C),
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (_detection == null) ...[
                  if (_imagePath != null)
                    Image.file(File(_imagePath!), fit: BoxFit.contain)
                  else if (_camera?.value.isInitialized == true)
                    LayoutBuilder(
                      builder: (context, size) {
                        final preview = _camera!.value.previewSize!;
                        return ClipRect(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: preview.height,
                              height: preview.width,
                              child: CameraPreview(_camera!),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    Center(
                      child: _unavailable
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                useMockApi
                                    ? '当前设备使用演示画面'
                                    : '相机不可用\n请检查相机权限，或从相册选择照片',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )
                          : const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                    ),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black54,
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black54,
                          ],
                          stops: [0, .3, .65, 1],
                        ),
                      ),
                    ),
                  ),
                ],
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            _control(
                              '退出扫描',
                              Icons.close_rounded,
                              _busy
                                  ? null
                                  : () {
                                      _disposeCamera();
                                      context.go('/home');
                                    },
                            ),
                            const Expanded(
                              child: Text(
                                'AI Scan',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _control(
                              '我的扫描反馈',
                              Icons.history_rounded,
                              _busy
                                  ? null
                                  : () =>
                                        context.push('/scan-feedback-history'),
                            ),
                            _control(
                              '闪光灯',
                              _flash
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              _busy || _detection != null || _imagePath != null
                                  ? null
                                  : _toggleFlash,
                            ),
                            _control(
                              '扫描帮助',
                              Icons.help_outline_rounded,
                              () => showModalBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (_) => SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      0,
                                      24,
                                      24,
                                    ),
                                    child: Text(
                                      widget.originalLocation
                                          ? '将一张或多张小卡完整放入画面，尽量避免重叠、反光和遮挡。\n\n拍摄或导入后自动定位并匹配图鉴，在原图中点击编号逐张核对。扫描不会自动加入心愿单或标记拥有。'
                                          : '将一张或多张小卡完整放入画面，尽量避免重叠、反光和遮挡。\n\n拍摄后自动框选小卡，默认全选。你可以取消不需要的小卡，点击“扫描”才开始匹配图鉴。扫描不会自动加入收藏或标记拥有。',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 6,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _detection != null
                                  ? '请选择要扫描的小卡'
                                  : '将一张或多张小卡完整放入画面',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_detection != null)
                        Expanded(
                          child: ScanSelection(
                            key: ValueKey(_detection!.sessionId),
                            detection: _detection!,
                            imageSize: _imageSize,
                            localImagePath: _imagePath,
                            busy: _busy,
                            error: _error,
                            onScan: _recognize,
                            onRetake: _retake,
                          ),
                        )
                      else ...[
                        Expanded(
                          child: _busy && !_pickingImage
                              ? const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        '正在检测小卡…',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox(),
                        ),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.all(20),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: FanColors.canvas,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _busy ? null : _retake,
                                        child: const Text('重新拍摄'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _busy ? null : _detect,
                                        child: const Text('重试检测'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (_error == null)
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                16,
                                24,
                                24,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _control(
                                    '相册',
                                    Icons.photo_library_outlined,
                                    _busy
                                        ? null
                                        : () => _capture(gallery: true),
                                  ),
                                  Semantics(
                                    button: true,
                                    label: '拍照检测小卡',
                                    child: GestureDetector(
                                      key: const Key('scan-shutter'),
                                      onTap: _busy ? null : () => _capture(),
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                        ),
                                        child: const DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _control(
                                    '切换相机',
                                    Icons.cameraswitch_outlined,
                                    _busy
                                        ? null
                                        : () {
                                            _lens =
                                                _lens ==
                                                    CameraLensDirection.back
                                                ? CameraLensDirection.front
                                                : CameraLensDirection.back;
                                            _initializeCamera();
                                          },
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

  Widget _buildOriginalLocation(BuildContext context) {
    final hasPhoto = _imagePath != null || _detection != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF17171D),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _control('关闭原图定位扫描', Icons.close_rounded, () {
                      _operation++;
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    }),
                    const Expanded(
                      child: Text(
                        'AI Scan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _control(
                      '闪光灯',
                      _flash ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      _busy || hasPhoto ? null : _toggleFlash,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: hasPhoto
                    ? ScanOriginalProgress(
                        detection: _detection,
                        localImagePath: _imagePath,
                        imageSize: _imageSize,
                      )
                    : _camera?.value.isInitialized == true
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: 1 / _camera!.value.aspectRatio,
                          child: CameraPreview(_camera!),
                        ),
                      )
                    : Center(
                        child: _unavailable
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  '相机暂不可用\n请检查相机权限，或从相册导入照片',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                  ),
                                ),
                              )
                            : const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                      ),
              ),
              if (_busy || hasPhoto || _error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: FanColors.canvas,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _detection == null
                              ? '正在识别小卡…'
                              : '正在匹配 ${_detection!.regions.length} 张小卡…',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (_error != null) ...[
                        Text(_error!, style: const TextStyle(fontSize: 15)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _retake,
                                child: const Text('重新拍摄'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  if (_detection != null) {
                                    _recognize(
                                      _detection!.regions
                                          .map((r) => r.id)
                                          .toSet(),
                                    );
                                  } else if (_imagePath != null) {
                                    _detect();
                                  } else {
                                    _capture(gallery: true);
                                  }
                                },
                                child: const Text('重试'),
                              ),
                            ),
                          ],
                        ),
                      ] else if (_lastResult != null) ...[
                        FilledButton(
                          onPressed: () => context.push(
                            '/scan-original-result',
                            extra: _lastResult,
                          ),
                          child: const Text('继续核对'),
                        ),
                        TextButton(
                          onPressed: _retake,
                          child: const Text('扫描新照片'),
                        ),
                      ] else ...[
                        const Text(
                          '未检测到小卡',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('请完整拍入小卡，避免反光或遮挡。'),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _retake,
                                child: const Text('重新拍摄'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  _detection = null;
                                  _capture(gallery: true);
                                },
                                child: const Text('重新选图'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '完整拍入，避免反光',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _control(
                        '相册导入',
                        Icons.photo_library_outlined,
                        () => _capture(gallery: true),
                      ),
                      Semantics(
                        button: true,
                        label: '拍照并自动识别小卡',
                        child: InkWell(
                          key: const Key('original-scan-shutter'),
                          onTap: () => _capture(),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 76,
                            height: 76,
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFF777780),
                                width: 4,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _control(String label, IconData icon, VoidCallback? onTap) =>
      IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, size: 24),
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white38,
          backgroundColor: Colors.black.withValues(alpha: .16),
          minimumSize: const Size(44, 44),
        ),
      );
}
