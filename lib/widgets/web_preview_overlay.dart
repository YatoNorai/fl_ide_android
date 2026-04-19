import 'dart:math' as math;

import 'package:dap_client/dap_client.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:provider/provider.dart';

// ── Snap coordinator ──────────────────────────────────────────────────────────
// Shared between the WebPreview bubble and the DAP execution overlay.
// Prevents the two docked overlays from visually overlapping when both are
// snapped to the same screen edge.

class SnapCoordinator extends ChangeNotifier {
  static const int slotWeb = 0;
  static const int slotDap = 1;

  final Map<int, _SnapSlot> _slots = {};

  void update(int slot,
      {required bool active,
      required bool left,
      required double y,
      required double h}) {
    final next = _SnapSlot(active: active, left: left, y: y, h: h);
    if (_slots[slot] == next) return;
    _slots[slot] = next;
    notifyListeners();
  }

  void clear(int slot) {
    if (_slots.remove(slot) != null) notifyListeners();
  }

  /// Returns a Y coordinate for [mySlot] that avoids overlap with the other
  /// slot when both are docked to the same edge.
  double resolveY(
      int mySlot, bool onLeft, double wantY, double ownH, double screenH) {
    for (final entry in _slots.entries) {
      if (entry.key == mySlot) continue;
      final other = entry.value;
      if (!other.active || other.left != onLeft) continue;

      final otherTop    = other.y;
      final otherBottom = other.y + other.h;
      final ownBottom   = wantY + ownH;

      if (wantY < otherBottom && ownBottom > otherTop) {
        // Overlapping — push self to the side that has more room.
        if (wantY <= otherTop) {
          return (otherTop - ownH - 4).clamp(0.0, screenH - ownH);
        } else {
          return (otherBottom + 4).clamp(0.0, screenH - ownH);
        }
      }
    }
    return wantY.clamp(0.0, screenH - ownH);
  }
}

class _SnapSlot {
  final bool active;
  final bool left;
  final double y;
  final double h;

  const _SnapSlot(
      {required this.active,
      required this.left,
      required this.y,
      required this.h});

  @override
  bool operator ==(Object other) =>
      other is _SnapSlot &&
      other.active == active &&
      other.left == left &&
      other.y == y &&
      other.h == h;

  @override
  int get hashCode => Object.hash(active, left, y, h);
}

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
  /// Optional shared coordinator that prevents this bubble from overlapping
  /// the DAP execution overlay when both are docked to the same edge.
  final SnapCoordinator? coordinator;
  final bool liquidGlass;

  const WebPreviewOverlay({
    super.key,
    required this.url,
    required this.onClose,
    required this.navigatorContext,
    this.coordinator,
    this.liquidGlass = false,
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

  /// Edge-snap state for the minimized bubble.
  bool _bubbleSnapped    = false;
  bool _bubbleSnapLeft   = true;
  /// Cumulative drag distance away from the snapped edge (resets on reversal).
  double _dragAwayAccum  = 0.0;
  static const double _kBubbleSnapThreshold = 64.0;
  static const double _kBubbleSize          = 56.0;
  static const double _kBubbleTabW          = 36.0; // visible width when snapped
  /// How far the user must drag back into the screen to un-snap.
  static const double _kUnSnapThreshold     = 28.0;

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
    widget.coordinator?.addListener(_onCoordChanged);
  }

  @override
  void dispose() {
    widget.coordinator?.removeListener(_onCoordChanged);
    widget.coordinator?.clear(SnapCoordinator.slotWeb);
    super.dispose();
  }

  // Coordinator changes only affect the snapped-bubble Y position.
  // The listener is kept solely so the SnapCoordinator can push updates;
  // rebuilds are now scoped via ListenableBuilder in the snapped-tab branch,
  // so this callback intentionally does nothing (the coordinator itself is the
  // listenable passed to ListenableBuilder).
  void _onCoordChanged() {}

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

  void _toggleMinimize() {
    setState(() {
      _minimized = !_minimized;
      _bubbleSnapped = false; // always start un-snapped when (re-)minimizing
      _dragAwayAccum = 0;
    });
    if (!_minimized) widget.coordinator?.clear(SnapCoordinator.slotWeb);
  }

  // ── Bubble edge-snap helpers ─────────────────────────────────────────────────

  void _onBubblePanUpdate(DragUpdateDetails d) {
    final size = MediaQuery.of(context).size;
    if (_bubbleSnapped) {
      // While snapped: allow Y-axis sliding along the edge.
      final newY = (_bubblePos.dy + d.delta.dy).clamp(0.0, size.height - _kBubbleSize);
      setState(() => _bubblePos = Offset(_bubblePos.dx, newY));
      // Notify coordinator of new desired Y so the other overlay adjusts.
      widget.coordinator?.update(SnapCoordinator.slotWeb,
          active: true, left: _bubbleSnapLeft, y: newY, h: _kBubbleSize);

      // Accumulate drag away from the edge.  Reversing direction resets the
      // counter so only a deliberate continuous drag un-snaps the bubble.
      final awayDelta = _bubbleSnapLeft ? d.delta.dx : -d.delta.dx;
      if (awayDelta > 0) {
        _dragAwayAccum += awayDelta;
      } else {
        _dragAwayAccum = 0;
      }
      if (_dragAwayAccum >= _kUnSnapThreshold) {
        setState(() {
          _bubbleSnapped = false;
          _dragAwayAccum = 0;
          _bubblePos = Offset(
            _bubbleSnapLeft ? _kBubbleTabW + 8 : size.width - _kBubbleSize - 8,
            _bubblePos.dy,
          );
        });
        widget.coordinator?.clear(SnapCoordinator.slotWeb);
      }
    } else {
      final nx = (_bubblePos.dx + d.delta.dx).clamp(0.0, size.width  - _kBubbleSize);
      final ny = (_bubblePos.dy + d.delta.dy).clamp(0.0, size.height - _kBubbleSize);
      setState(() => _bubblePos = Offset(nx, ny));
    }
  }

  void _onBubblePanEnd(DragEndDetails d) {
    if (_bubbleSnapped) return;
    final size    = MediaQuery.of(context).size;
    final velX    = d.velocity.pixelsPerSecond.dx;
    final nearLeft  = _bubblePos.dx < _kBubbleSnapThreshold || velX < -500;
    final nearRight = _bubblePos.dx + _kBubbleSize > size.width - _kBubbleSnapThreshold || velX > 500;
    if (nearLeft && !nearRight) {
      setState(() { _bubbleSnapped = true; _bubbleSnapLeft = true; _dragAwayAccum = 0; });
      widget.coordinator?.update(SnapCoordinator.slotWeb,
          active: true, left: true, y: _bubblePos.dy, h: _kBubbleSize);
    } else if (nearRight) {
      setState(() { _bubbleSnapped = true; _bubbleSnapLeft = false; _dragAwayAccum = 0; });
      widget.coordinator?.update(SnapCoordinator.slotWeb,
          active: true, left: false, y: _bubblePos.dy, h: _kBubbleSize);
    }
  }

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
      // ── Snapped to edge: show a slim tab protruding from the screen edge ──
      if (_bubbleSnapped) {
        const tabH   = _kBubbleSize;
        const tabW   = _kBubbleTabW;
        final radius = const Radius.circular(12);
        final br = _bubbleSnapLeft
            ? BorderRadius.only(topRight: radius, bottomRight: radius)
            : BorderRadius.only(topLeft: radius, bottomLeft: radius);
        final size = MediaQuery.of(context).size;

        // Static content that never changes while snapped — hoisted as `child`
        // so ListenableBuilder does not recreate it on coordinator updates.
        final tabContent = Material(
          elevation: 8,
          borderRadius: br,
          color: cs.primaryContainer,
          child: Container(
            width: tabW,
            height: tabH,
            decoration: BoxDecoration(
              borderRadius: br,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone_android_rounded, size: 18, color: cs.primary),
                if (_isLoading) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: cs.primary),
                  ),
                ],
              ],
            ),
          ),
        );

        // ListenableBuilder scopes rebuilds to only the Positioned wrapper,
        // so coordinator Y changes do NOT rebuild the entire overlay widget.
        final coordinator = widget.coordinator;
        if (coordinator != null) {
          return ListenableBuilder(
            listenable: coordinator,
            child: GestureDetector(
              onPanUpdate: _onBubblePanUpdate,
              onPanEnd: _onBubblePanEnd,
              onTap: () {
                setState(() {
                  _bubbleSnapped = false;
                  _dragAwayAccum = 0;
                  _bubblePos = Offset(
                    _bubbleSnapLeft ? tabW + 8 : size.width - _kBubbleSize - 8,
                    _bubblePos.dy,
                  );
                });
                coordinator.clear(SnapCoordinator.slotWeb);
              },
              child: tabContent,
            ),
            builder: (context, child) {
              final displayY = coordinator.resolveY(
                SnapCoordinator.slotWeb, _bubbleSnapLeft,
                _bubblePos.dy, tabH, size.height,
              );
              return Positioned(
                left:  _bubbleSnapLeft ? 0 : null,
                right: _bubbleSnapLeft ? null : 0,
                top:   displayY,
                child: child!,
              );
            },
          );
        }

        // Fallback when no coordinator is provided (no overlap resolution needed).
        final displayY = _bubblePos.dy.clamp(0.0, size.height - tabH);
        return Positioned(
          left:  _bubbleSnapLeft ? 0 : null,
          right: _bubbleSnapLeft ? null : 0,
          top:   displayY,
          child: GestureDetector(
            onPanUpdate: _onBubblePanUpdate,
            onPanEnd: _onBubblePanEnd,
            onTap: () {
              setState(() {
                _bubbleSnapped = false;
                _dragAwayAccum = 0;
                _bubblePos = Offset(
                  _bubbleSnapLeft ? tabW + 8 : size.width - _kBubbleSize - 8,
                  _bubblePos.dy,
                );
              });
            },
            child: tabContent,
          ),
        );
      }

      // ── Free-floating bubble ───────────────────────────────────────────────
      return Positioned(
        left: _bubblePos.dx,
        top: _bubblePos.dy,
        child: GestureDetector(
          onPanUpdate: _onBubblePanUpdate,
          onPanEnd:    _onBubblePanEnd,
          onTap: _toggleMinimize,
          child: Material(
            elevation: 8,
            color: cs.primaryContainer,
            shape: const CircleBorder(),
            child: SizedBox(
              width: _kBubbleSize,
              height: _kBubbleSize,
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
    final isDark = cs.brightness == Brightness.dark;
    final panelContent = SafeArea(
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
        );
      

    return Positioned.fill(
      child: widget.liquidGlass
          ? LiquidGlass.withOwnLayer(
              settings: LiquidGlassSettings(
                glassColor: cs.surface.withValues(alpha: 0.88),
                blur: 3.0,
                thickness: 50.0,
                lightIntensity: isDark ? 0.7 : 1.0,
                ambientStrength: isDark ? 0.2 : 0.5,
                lightAngle: math.pi / 4,
                refractiveIndex: 1.18,
                saturation: 1.4,
                chromaticAberration: 0.4,
              ),
              shape: LiquidRoundedRectangle(borderRadius: 0),
              child: GlassGlow(
                child: Material(type: MaterialType.transparency, child: panelContent),
              ),
            )
          : Material(color: cs.surface, child: panelContent),
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
