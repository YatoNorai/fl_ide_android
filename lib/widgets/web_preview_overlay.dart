import 'dart:math' as math;

import 'package:dap_client/dap_client.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

// ── Network preset ────────────────────────────────────────────────────────────

enum _NetMode {
  online('Online', Icons.wifi_rounded),
  offline('Offline', Icons.wifi_off_rounded);

  const _NetMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

// ── Device catalogue ──────────────────────────────────────────────────────────

class _DeviceEntry {
  final String name;
  final DeviceInfo info;
  final bool isIos;
  const _DeviceEntry(this.name, this.info, {this.isIos = false});
}

final _kDevices = [
  _DeviceEntry('Galaxy A50', Devices.android.samsungGalaxyA50),
  _DeviceEntry('Galaxy S20', Devices.android.samsungGalaxyS20),
  _DeviceEntry('iPhone SE', Devices.ios.iPhoneSE, isIos: true),
  _DeviceEntry('iPhone 13', Devices.ios.iPhone13, isIos: true),
  _DeviceEntry('iPhone 13 Mini', Devices.ios.iPhone13Mini, isIos: true),
];

// ── Screen positioning helpers ────────────────────────────────────────────────

/// Returns the screen bounding rect in the *rendered* overlay coordinate space
/// after taking the current [orientation] into account.
///
/// For landscape the canvas transform is translate(0, W*s), rotate(−π/2),
/// scale(s,s), which maps native portrait (nx, ny) → overlay (ny*s, (W−nx)*s).
/// Inverting that gives the landscape screen rect used to position the WebView.
Rect _screenRectInFrame(DeviceInfo d, Orientation orientation) {
  final raw = d.screenPath.getBounds();
  if (!d.isLandscape(orientation)) return raw;

  final W = d.frameSize.width;
  return Rect.fromLTRB(raw.top, W - raw.right, raw.bottom, W - raw.left);
}

/// Width of the rendered frame for [orientation].
double _renderedFrameWidth(DeviceInfo d, Orientation orientation) =>
    d.isLandscape(orientation) ? d.frameSize.height : d.frameSize.width;

/// Height of the rendered frame for [orientation].
double _renderedFrameHeight(DeviceInfo d, Orientation orientation) =>
    d.isLandscape(orientation) ? d.frameSize.width : d.frameSize.height;

// ── Overlay ───────────────────────────────────────────────────────────────────

/// Floating, draggable device-preview overlay that renders a Flutter web app
/// inside a realistic phone bezel.
///
/// Rendering layers (bottom → top):
///   1. [InAppWebView] positioned at the exact scaled screen-area rect.
///      Platform views must NOT go through Flutter transforms, so we compute
///      the screen rect in overlay coordinates and use [Positioned] directly.
///   2. [_FrameBezelPainter] drawn on top via [CustomPaint]. It clips out
///      the screen path before delegating to [DeviceInfo.framePainter], so
///      only the bezel is painted and the WebView shows through.
class WebPreviewOverlay extends StatefulWidget {
  final String url;
  final VoidCallback onClose;
  final Offset initialPos;

  const WebPreviewOverlay({
    super.key,
    required this.url,
    required this.onClose,
    this.initialPos = const Offset(16, 72),
  });

  @override
  State<WebPreviewOverlay> createState() => _WebPreviewOverlayState();
}

class _WebPreviewOverlayState extends State<WebPreviewOverlay> {
  static const _kMinFrameW = 180.0;
  static const _kMaxFrameW = 480.0;
  static const _kDefaultFrameW = 270.0;

  /// Current overlay width — changed by the resize handle.
  double _frameW = _kDefaultFrameW;

  late Offset _pos;
  bool _minimized = false;

  _DeviceEntry _entry = _kDevices[0];
  Orientation _orientation = Orientation.portrait;
  _NetMode _net = _NetMode.online;

  InAppWebViewController? _ctrl;
  bool _isLoading = true;
  String? _loadError;

  final _webSettings = InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    clearCache: true,
    userAgent:
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  );

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
    _setupServiceWorker();
  }

  Future<void> _setupServiceWorker() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final sw = ServiceWorkerController.instance();
      await sw.setServiceWorkerClient(
        ServiceWorkerClient(shouldInterceptRequest: (r) async => null),
      );
    } catch (_) {}
  }

  // ── Geometry ────────────────────────────────────────────────────────────────

  /// Scale factor: _frameW / rendered-frame-width.
  double get _scale {
    final rw = _renderedFrameWidth(_entry.info, _orientation);
    return _frameW / rw;
  }

  /// Overlay frame height after scaling.
  double get _frameH {
    final rh = _renderedFrameHeight(_entry.info, _orientation);
    return rh * _scale;
  }

  /// Screen area in overlay coordinates (already scaled).
  Rect get _scaledScreen {
    final r = _screenRectInFrame(_entry.info, _orientation);
    final s = _scale;
    return Rect.fromLTWH(r.left * s, r.top * s, r.width * s, r.height * s);
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _reload() {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    _ctrl?.reload();
  }

  void _toggleMinimized() {
    setState(() => _minimized = !_minimized);
    // Clamp bubble position when restoring
    if (!_minimized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final mq = MediaQuery.of(context);
        final minTop = mq.padding.top + kToolbarHeight + 3;
        final totalH = _frameH + 44;
        final clamped = Offset(
          _pos.dx.clamp(0.0, (mq.size.width - _frameW).toDouble()),
          _pos.dy.clamp(minTop, (mq.size.height - totalH).toDouble()),
        );
        if (clamped != _pos) setState(() => _pos = clamped);
      });
    }
  }

  void _toggleOrientation() {
    setState(() {
      _orientation = _orientation == Orientation.portrait
          ? Orientation.landscape
          : Orientation.portrait;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mq = MediaQuery.of(context);
      final minTop = mq.padding.top + kToolbarHeight + 3;
      final totalH = _frameH + 44;
      final clamped = Offset(
        _pos.dx.clamp(0.0, (mq.size.width - _frameW).toDouble()),
        _pos.dy.clamp(minTop, (mq.size.height - totalH).toDouble()),
      );
      if (clamped != _pos) setState(() => _pos = clamped);
    });
  }

  Future<void> _setNetwork(_NetMode mode) async {
    setState(() => _net = mode);
    final offline = mode == _NetMode.offline;
    await _ctrl?.setSettings(
      settings: InAppWebViewSettings(blockNetworkLoads: offline),
    );
    await _ctrl?.evaluateJavascript(
      source:
          "window.dispatchEvent(new Event('${offline ? 'offline' : 'online'}'))",
    );
    if (!offline) _reload();
  }

  void _showDevicePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DevicePickerSheet(
        current: _entry,
        onSelect: (e) {
          setState(() => _entry = e);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showNetworkPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _NetPickerSheet(
        current: _net,
        onSelect: (m) {
          Navigator.pop(context);
          _setNetwork(m);
        },
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  Widget _buildBubble(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onTap: _toggleMinimized,
        onPanUpdate: (d) {
          final mq = MediaQuery.of(context);
          setState(() {
            _pos = Offset(
              (_pos.dx + d.delta.dx).clamp(0.0, mq.size.width - 60.0),
              (_pos.dy + d.delta.dy).clamp(0.0, mq.size.height - 60.0),
            );
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _entry.isIos
                  ? Icons.phone_iphone_rounded
                  : Icons.phone_android_rounded,
              color: cs.primary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_minimized) return _buildBubble(context);

    final screen = _scaledScreen;
    final frameH = _frameH;

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: _frameW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Toolbar(
                entry: _entry,
                orientation: _orientation,
                net: _net,
                isLoading: _isLoading,
                loadError: _loadError,
                onDrag: (d) {
                  final mq = MediaQuery.of(context);
                  final scrW = mq.size.width;
                  final scrH = mq.size.height;
                  final minTop = mq.padding.top + kToolbarHeight + 3;
                  final totalH = _frameH + 44;
                  setState(() {
                    _pos = Offset(
                      (_pos.dx + d.dx).clamp(0.0, (scrW - _frameW).toDouble()),
                      (_pos.dy + d.dy).clamp(minTop, (scrH - totalH).toDouble()),
                    );
                  });
                },
                onDevice: _showDevicePicker,
                onOrientation: _toggleOrientation,
                onNetwork: _showNetworkPicker,
                onReload: _reload,
                onMinimize: _toggleMinimized,
                onClose: widget.onClose,
              ),
              Stack(
                children: [
                  SizedBox(
                    width: _frameW,
                    height: frameH,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // ── 1. WebView: sized to the scaled screen area ──────
                        Positioned(
                          left: screen.left,
                          top: screen.top,
                          width: screen.width,
                          height: screen.height,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(_scale * 40),
                            child: InAppWebView(
                              key: ValueKey('wv_${_orientation.name}'),
                              initialUrlRequest:
                                  URLRequest(url: WebUri(widget.url)),
                              initialSettings: _webSettings,
                              onWebViewCreated: (c) => _ctrl = c,
                              onLoadStart: (_, __) => setState(() {
                                _isLoading = true;
                                _loadError = null;
                              }),
                              onLoadStop: (_, __) =>
                                  setState(() => _isLoading = false),
                              onReceivedError: (_, __, error) => setState(() {
                                _isLoading = false;
                                if (error.type !=
                                    WebResourceErrorType.CANCELLED) {
                                  _loadError = error.description;
                                }
                              }),
                              onConsoleMessage: (_, m) => debugPrint(
                                  '[WebPreview] ${m.messageLevel}: ${m.message}'),
                            ),
                          ),
                        ),

                        // ── 2. Device frame bezel: CustomPainter drawn on top
                        IgnorePointer(
                          child: SizedBox(
                            width: _frameW,
                            height: frameH,
                            child: CustomPaint(
                              painter: _FrameBezelPainter(
                                device: _entry.info,
                                orientation: _orientation,
                                scale: _scale,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── 3. Resize handle — bottom-right corner ───────────────
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) {
                        final mq = MediaQuery.of(context);
                        setState(() {
                          _frameW = (_frameW + d.delta.dx)
                              .clamp(_kMinFrameW, _kMaxFrameW);
                          // keep overlay on screen after resize
                          final maxX = mq.size.width - _frameW;
                          if (_pos.dx > maxX) _pos = Offset(maxX, _pos.dy);
                        });
                      },
                      child: _ResizeHandle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Frame bezel painter ───────────────────────────────────────────────────────

/// Paints only the device bezel (everything except the screen area).
///
/// The [device.framePainter] draws an opaque phone body that covers the screen.
/// We counter this by clipping the canvas to the inverse of [device.screenPath]
/// (an even-odd donut) before delegating to [framePainter], so the screen area
/// stays transparent and the [InAppWebView] below shows through exactly.
///
/// Canvas transform (portrait):
///   canvas.scale(scale, scale) → native frame coordinates
///
/// Canvas transform (landscape):
///   canvas.translate(0, frameSize.width * scale)
///   canvas.rotate(-π/2)
///   canvas.scale(scale, scale) → native frame coordinates
///
/// Both transforms match the WebView's [_scaledScreen] position exactly.
class _FrameBezelPainter extends CustomPainter {
  final DeviceInfo device;
  final Orientation orientation;
  final double scale;

  const _FrameBezelPainter({
    required this.device,
    required this.orientation,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final d = device;
    final s = scale;
    final isLandscape = d.isLandscape(orientation);

    canvas.save();

    if (isLandscape) {
      // Map native portrait frame (W × H) to landscape overlay:
      // native (nx, ny) → overlay (ny*s, (W−nx)*s)
      canvas.translate(0, d.frameSize.width * s);
      canvas.rotate(-math.pi / 2);
    }
    canvas.scale(s, s);

    // Donut clip: full frame rect minus screen path.
    // The even-odd fill rule creates a hole wherever screenPath overlaps,
    // so framePainter can't paint over the screen area.
    final clipPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, d.frameSize.width, d.frameSize.height))
      ..addPath(d.screenPath, Offset.zero);
    clipPath.fillType = PathFillType.evenOdd;
    canvas.clipPath(clipPath);

    d.framePainter.paint(canvas, d.frameSize);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FrameBezelPainter old) =>
      old.device != device ||
      old.orientation != orientation ||
      old.scale != scale;
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final _DeviceEntry entry;
  final Orientation orientation;
  final _NetMode net;
  final bool isLoading;
  final String? loadError;
  final void Function(Offset) onDrag;
  final VoidCallback onDevice;
  final VoidCallback onOrientation;
  final VoidCallback onNetwork;
  final VoidCallback onReload;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _Toolbar({
    required this.entry,
    required this.orientation,
    required this.net,
    required this.isLoading,
    required this.loadError,
    required this.onDrag,
    required this.onDevice,
    required this.onOrientation,
    required this.onNetwork,
    required this.onReload,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = loadError != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => onDrag(d.delta),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: hasError ? cs.errorContainer : cs.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Device selector chip — Flexible so it shrinks, never pushes right btns off screen
            Flexible(
              child: GestureDetector(
                onTap: onDevice,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.isIos
                            ? Icons.phone_iphone_rounded
                            : Icons.phone_android_rounded,
                        size: 11,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          entry.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      Icon(Icons.expand_more_rounded,
                          size: 12, color: cs.primary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Drag indicator (centre hint)
            Icon(Icons.drag_indicator_rounded,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.25)),
            const SizedBox(width: 4),
            // Orientation
            _ToolBtn(
              icon: orientation == Orientation.portrait
                  ? Icons.stay_current_portrait_rounded
                  : Icons.stay_current_landscape_rounded,
              onTap: onOrientation,
              cs: cs,
            ),
            // Network
            _ToolBtn(
              icon: net.icon,
              onTap: onNetwork,
              cs: cs,
              color: net == _NetMode.offline ? cs.error : null,
            ),
            // Reload / Loading
            SizedBox(
              width: 28,
              height: 28,
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: cs.primary),
                      ),
                    )
                  : _ToolBtn(
                      icon: Icons.refresh_rounded,
                      onTap: onReload,
                      cs: cs,
                      color: hasError ? cs.error : null,
                    ),
            ),
            // Debug actions popup (single btn — avoids overflow when debug active)
            Consumer<DebugProvider>(
              builder: (context, dbg, _) {
                if (!dbg.isRunning) return const SizedBox.shrink();
                return _DebugPopupBtn(cs: cs, dbg: dbg);
              },
            ),
            // Minimize to bubble
            _ToolBtn(
                icon: Icons.picture_in_picture_alt_rounded,
                onTap: onMinimize,
                cs: cs),
            // Close
            _ToolBtn(icon: Icons.close_rounded, onTap: onClose, cs: cs),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  final Color? color;

  const _ToolBtn({
    required this.icon,
    required this.onTap,
    required this.cs,
    this.color,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: color ?? cs.onSurfaceVariant),
        ),
      );
}

// ── Resize handle ─────────────────────────────────────────────────────────────

class _ResizeHandle extends StatelessWidget {
  final Color color;
  const _ResizeHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(painter: _ResizeHandlePainter(color: color)),
    );
  }
}

class _ResizeHandlePainter extends CustomPainter {
  final Color color;
  const _ResizeHandlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Three diagonal lines in the bottom-right corner
    for (int i = 1; i <= 3; i++) {
      final offset = i * 6.0;
      canvas.drawLine(
        Offset(size.width - offset, size.height),
        Offset(size.width, size.height - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ResizeHandlePainter old) => old.color != color;
}

// ── Debug popup button ────────────────────────────────────────────────────────

/// Single-button replacement for hot-reload + hot-restart so the toolbar Row
/// never overflows the fixed 270 px width.
class _DebugPopupBtn extends StatelessWidget {
  final ColorScheme cs;
  final DebugProvider dbg;

  const _DebugPopupBtn({required this.cs, required this.dbg});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(Icons.electric_bolt_rounded,
          size: 16, color: Colors.orange),
      iconSize: 16,
      constraints: const BoxConstraints(minWidth: 28, maxWidth: 28,
          minHeight: 28, maxHeight: 28),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) {
        if (v == 'reload') dbg.hotReload();
        if (v == 'restart') dbg.restart();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'reload',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.electric_bolt_rounded,
                  size: 16, color: Colors.orange),
              const SizedBox(width: 10),
              Text('Hot Reload',
                  style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'restart',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.restart_alt_rounded,
                  size: 16, color: cs.primary),
              const SizedBox(width: 10),
              Text('Hot Restart',
                  style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Device picker ─────────────────────────────────────────────────────────────

class _DevicePickerSheet extends StatelessWidget {
  final _DeviceEntry current;
  final ValueChanged<_DeviceEntry> onSelect;

  const _DevicePickerSheet(
      {required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          _SheetHandle(cs: cs),
          const SizedBox(height: 12),
          _SheetTitle(icon: Icons.devices_rounded, label: 'Device', cs: cs),
          const SizedBox(height: 8),
          for (final e in _kDevices)
            _DeviceTile(
              entry: e,
              isSelected: e.name == current.name,
              onTap: () => onSelect(e),
              cs: cs,
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final _DeviceEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _DeviceTile(
      {required this.entry,
      required this.isSelected,
      required this.onTap,
      required this.cs});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                entry.isIos
                    ? Icons.phone_iphone_rounded
                    : Icons.phone_android_rounded,
                size: 16,
                color:
                    isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          isSelected ? cs.primary : cs.onSurface,
                    ),
                  ),
                  Text(
                    '${entry.info.screenSize.width.toInt()} × '
                    '${entry.info.screenSize.height.toInt()} · '
                    '${entry.info.pixelRatio}×',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded,
                  size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

// ── Network picker ────────────────────────────────────────────────────────────

class _NetPickerSheet extends StatelessWidget {
  final _NetMode current;
  final ValueChanged<_NetMode> onSelect;

  const _NetPickerSheet(
      {required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          _SheetHandle(cs: cs),
          const SizedBox(height: 12),
          _SheetTitle(
              icon: Icons.network_check_rounded,
              label: 'Network',
              cs: cs),
          const SizedBox(height: 8),
          for (final m in _NetMode.values)
            InkWell(
              onTap: () => onSelect(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: m == current
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        m.icon,
                        size: 16,
                        color: m == _NetMode.offline
                            ? (m == current
                                ? cs.error
                                : cs.onSurfaceVariant)
                            : (m == current
                                ? cs.primary
                                : cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: m == current
                            ? cs.primary
                            : cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (m == current)
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: cs.primary),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Shared sheet components ───────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  final ColorScheme cs;
  const _SheetHandle({required this.cs});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme cs;
  const _SheetTitle(
      {required this.icon, required this.label, required this.cs});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      );
}
