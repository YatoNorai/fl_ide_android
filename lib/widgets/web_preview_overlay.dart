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

Rect _screenRectInFrame(DeviceInfo d, Orientation orientation) {
  final raw = d.screenPath.getBounds();
  if (!d.isLandscape(orientation)) return raw;
  final W = d.frameSize.width;
  return Rect.fromLTRB(raw.top, W - raw.right, raw.bottom, W - raw.left);
}

double _renderedFrameWidth(DeviceInfo d, Orientation orientation) =>
    d.isLandscape(orientation) ? d.frameSize.height : d.frameSize.width;

double _renderedFrameHeight(DeviceInfo d, Orientation orientation) =>
    d.isLandscape(orientation) ? d.frameSize.width : d.frameSize.height;

// ── Overlay ───────────────────────────────────────────────────────────────────

/// Full-screen device-preview panel (inserted via OverlayEntry so it can be
/// closed programmatically by the DebugProvider listener).
///
/// Renders a Flutter web app inside the workspace as a page-like surface.
/// The device frame is scaled to fit the available area and can be hidden
/// via the toolbar toggle button.
class WebPreviewOverlay extends StatefulWidget {
  final String url;
  final VoidCallback onClose;
  /// A context that has a Navigator ancestor — needed for showModalBottomSheet
  /// because OverlayEntry builders run above the app's Navigator.
  final BuildContext navigatorContext;

  const WebPreviewOverlay({
    super.key,
    required this.url,
    required this.onClose,
    required this.navigatorContext,
  });

  @override
  State<WebPreviewOverlay> createState() => _WebPreviewOverlayState();
}

class _WebPreviewOverlayState extends State<WebPreviewOverlay> {
  _DeviceEntry _entry = _kDevices[0];
  Orientation _orientation = Orientation.portrait;
  _NetMode _net = _NetMode.online;
  bool _showFrame = true;

  /// Whether the panel is collapsed to a floating bubble.
  bool _minimized = false;
  Offset _bubblePos = const Offset(16, 120);

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

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _toggleMinimize() => setState(() => _minimized = !_minimized);

  void _reload() {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    _ctrl?.reload();
  }

  void _toggleOrientation() {
    setState(() {
      _orientation = _orientation == Orientation.portrait
          ? Orientation.landscape
          : Orientation.portrait;
    });
  }

  void _toggleFrame() => setState(() => _showFrame = !_showFrame);

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
      context: widget.navigatorContext,
      backgroundColor: Colors.transparent,
      builder: (_) => _DevicePickerSheet(
        current: _entry,
        onSelect: (e) {
          setState(() => _entry = e);
          Navigator.pop(widget.navigatorContext);
        },
      ),
    );
  }

  void _showNetworkPicker() {
    showModalBottomSheet<void>(
      context: widget.navigatorContext,
      backgroundColor: Colors.transparent,
      builder: (_) => _NetPickerSheet(
        current: _net,
        onSelect: (m) {
          Navigator.pop(widget.navigatorContext);
          _setNetwork(m);
        },
      ),
    );
  }

  // ── WebView helper ───────────────────────────────────────────────────────────

  Widget _buildWebView() => InAppWebView(
        key: ValueKey('wv_${_orientation.name}'),
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: _webSettings,
        onWebViewCreated: (c) => _ctrl = c,
        onLoadStart: (_, __) => setState(() {
          _isLoading = true;
          _loadError = null;
        }),
        onLoadStop: (_, __) => setState(() => _isLoading = false),
        onReceivedError: (_, __, error) => setState(() {
          _isLoading = false;
          if (error.type != WebResourceErrorType.CANCELLED) {
            _loadError = error.description;
          }
        }),
        onConsoleMessage: (_, m) =>
            debugPrint('[WebPreview] ${m.messageLevel}: ${m.message}'),
      );

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ── Minimized bubble ───────────────────────────────────────────────────
    if (_minimized) {
      return Positioned(
        left: _bubblePos.dx,
        top: _bubblePos.dy,
        child: GestureDetector(
          onPanUpdate: (d) =>
              setState(() => _bubblePos += d.delta),
          onTap: _toggleMinimize,
          child: Material(
            elevation: 8,
            color: cs.primaryContainer,
            shape: const CircleBorder(),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.phone_android_rounded,
                      size: 24, color: cs.primary),
                  if (_isLoading)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Full-screen panel ──────────────────────────────────────────────────
    return Positioned.fill(
      child: Material(
        color: cs.surface,
        child: SafeArea(
          child: Column(
            children: [
              _PageToolbar(
                entry: _entry,
                orientation: _orientation,
                net: _net,
                showFrame: _showFrame,
                isLoading: _isLoading,
                loadError: _loadError,
                onDevice: _showDevicePicker,
                onOrientation: _toggleOrientation,
                onNetwork: _showNetworkPicker,
                onReload: _reload,
                onToggleFrame: _toggleFrame,
                onMinimize: _toggleMinimize,
                onClose: widget.onClose,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    if (!_showFrame) {
                      // Plain full-area web view with no bezel
                      return _buildWebView();
                    }

                    // Scaled device frame centered in available space
                    final W = constraints.maxWidth;
                    final H = constraints.maxHeight;
                    final fw = _renderedFrameWidth(_entry.info, _orientation);
                    final fh = _renderedFrameHeight(_entry.info, _orientation);
                    // 0.92 → 4% padding on each side so the frame never
                    // touches the edges of the screen.
                    final scale = math.min(W / fw, H / fh) * 0.92;
                    final ox = (W - fw * scale) / 2;
                    final oy = (H - fh * scale) / 2;
                    final screen =
                        _screenRectInFrame(_entry.info, _orientation);

                    return Stack(
                      children: [
                        // ── 1. WebView at exact scaled screen area ───────────
                        Positioned(
                          left: ox + screen.left * scale,
                          top: oy + screen.top * scale,
                          width: screen.width * scale,
                          height: screen.height * scale,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(scale * 40),
                            child: _buildWebView(),
                          ),
                        ),
                        // ── 2. Device bezel painted over the WebView ─────────
                        Positioned(
                          left: ox,
                          top: oy,
                          width: fw * scale,
                          height: fh * scale,
                          child: IgnorePointer(
                            child: CustomPaint(
                              size: Size(fw * scale, fh * scale),
                              painter: _FrameBezelPainter(
                                device: _entry.info,
                                orientation: _orientation,
                                scale: scale,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Frame bezel painter ───────────────────────────────────────────────────────

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
      canvas.translate(0, d.frameSize.width * s);
      canvas.rotate(-math.pi / 2);
    }
    canvas.scale(s, s);

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

// ── Page toolbar ──────────────────────────────────────────────────────────────

class _PageToolbar extends StatelessWidget {
  final _DeviceEntry entry;
  final Orientation orientation;
  final _NetMode net;
  final bool showFrame;
  final bool isLoading;
  final String? loadError;
  final VoidCallback onDevice;
  final VoidCallback onOrientation;
  final VoidCallback onNetwork;
  final VoidCallback onReload;
  final VoidCallback onToggleFrame;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _PageToolbar({
    required this.entry,
    required this.orientation,
    required this.net,
    required this.showFrame,
    required this.isLoading,
    required this.loadError,
    required this.onDevice,
    required this.onOrientation,
    required this.onNetwork,
    required this.onReload,
    required this.onToggleFrame,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = loadError != null;

    return Container(
      height: 44,
       
      decoration: BoxDecoration(
        color: hasError ? cs.errorContainer : cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outline.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // Device selector chip
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
          const Spacer(),
          // Orientation
          _ToolBtn(
            icon: orientation == Orientation.portrait
                ? Icons.stay_current_portrait_rounded
                : Icons.stay_current_landscape_rounded,
            onTap: onOrientation,
            cs: cs,
          ),
          // Network
/*           _ToolBtn(
            icon: net.icon,
            onTap: onNetwork,
            cs: cs,
            color: net == _NetMode.offline ? cs.error : null,
          ), */
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
          // Debug actions popup
          Consumer<DebugProvider>(
            builder: (context, dbg, _) {
              if (!dbg.isRunning) return const SizedBox.shrink();
              return _DebugPopupBtn(
                cs: cs,
                dbg: dbg,
                onReloadWebView: onReload,
              );
            },
          ),
          // Toggle device frame — phone icon when frame is visible,
          // crop_free (full-screen) icon when frame is hidden
          _ToolBtn(
            icon: showFrame
                ? Icons.phone_android_rounded
                : Icons.crop_free_rounded,
            onTap: onToggleFrame,
            cs: cs,
            color: showFrame ? cs.primary : cs.onSurfaceVariant,
          ),
          // Minimize to floating bubble
          _ToolBtn(
            icon: Icons.bubble_chart_rounded,
            onTap: onMinimize,
            cs: cs,
          ),
          // Close
          _ToolBtn(icon: Icons.close_rounded, onTap: onClose, cs: cs),
          const SizedBox(width: 4),
        ],
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

// ── Debug popup button ────────────────────────────────────────────────────────

class _DebugPopupBtn extends StatelessWidget {
  final ColorScheme cs;
  final DebugProvider dbg;
  /// Called to reload the WebView (used for Metro sessions).
  final VoidCallback onReloadWebView;

  const _DebugPopupBtn({
    required this.cs,
    required this.dbg,
    required this.onReloadWebView,
  });

  @override
  Widget build(BuildContext context) {
    // Metro sessions have no DAP — offer WebView reload + Metro restart instead.
    if (dbg.isMetroSession) {
      return PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.electric_bolt_rounded,
            size: 16, color: Colors.deepOrange),
        iconSize: 16,
        constraints: const BoxConstraints(
            minWidth: 28, maxWidth: 28, minHeight: 28, maxHeight: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onSelected: (v) {
          if (v == 'webReload') onReloadWebView();
          if (v == 'metroStop') dbg.stopSession();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'webReload',
            height: 40,
            child: Row(
              children: [
                Icon(Icons.refresh_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 10),
                Text('Recarregar preview',
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'metroStop',
            height: 40,
            child: Row(
              children: [
                Icon(Icons.stop_circle_outlined, size: 16, color: cs.error),
                const SizedBox(width: 10),
                Text('Parar Metro',
                    style: TextStyle(fontSize: 13, color: cs.error)),
              ],
            ),
          ),
        ],
      );
    }

    // Flutter DAP session — hot reload / restart via DAP.
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.electric_bolt_rounded,
          size: 16, color: Colors.orange),
      iconSize: 16,
      constraints: const BoxConstraints(
          minWidth: 28, maxWidth: 28, minHeight: 28, maxHeight: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              const Icon(Icons.electric_bolt_rounded,
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
              Icon(Icons.restart_alt_rounded, size: 16, color: cs.primary),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
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
                      color: isSelected ? cs.primary : cs.onSurface,
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
              Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
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
              icon: Icons.network_check_rounded, label: 'Network', cs: cs),
          const SizedBox(height: 8),
          for (final m in _NetMode.values)
            InkWell(
              onTap: () => onSelect(m),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            ? (m == current ? cs.error : cs.onSurfaceVariant)
                            : (m == current ? cs.primary : cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: m == current ? cs.primary : cs.onSurface,
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
