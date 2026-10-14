import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../adaptive/ep_widgets.dart';
import '../l10n.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/brand_mark.dart';

/// Whether biometric / passcode lock is on (stored with the app settings).
final appLockEnabledProvider = AsyncNotifierProvider<AppLockSetting, bool>(AppLockSetting.new);

class AppLockSetting extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async => (await ref.read(secureStoreProvider).readSettings())['app_lock'] == true;

  /// Turning the lock on requires a successful authentication first, so a
  /// user can't lock themselves out with a device that can't authenticate.
  Future<bool> set(bool enabled, {required String reason}) async {
    if (enabled) {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      final ok = await auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
      if (!ok) return false;
    }
    await ref.read(secureStoreProvider).updateSettings((s) => s['app_lock'] = enabled);
    state = AsyncData(enabled);
    return true;
  }
}

/// Wraps the whole app: covers content in the app switcher and asks for
/// biometrics after more than [grace] in the background or on cold start.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child, this.grace = const Duration(minutes: 1)});

  final Widget child;
  final Duration grace;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _locked = true; // until the setting loads; cleared if lock is off
  bool _obscured = false;
  bool _authenticating = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = ref.read(appLockEnabledProvider).value ?? false;
    switch (state) {
      case AppLifecycleState.inactive || AppLifecycleState.hidden:
        if (enabled) setState(() => _obscured = true);
      case AppLifecycleState.paused:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final away = _backgroundedAt == null ? Duration.zero : DateTime.now().difference(_backgroundedAt!);
        _backgroundedAt = null;
        setState(() {
          _obscured = false;
          if (enabled && away > widget.grace) _locked = true;
        });
        if (_locked && enabled) _unlock();
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: context.l10n.lockReason,
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) setState(() => _locked = false);
    } on Object {
      // Stay locked; the button lets the user retry.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appLockEnabledProvider, (prev, next) {
      final was = prev?.value;
      final now = next.value;
      if (was == null && now == true) {
        _unlock(); // cold start with lock on
      } else if (now != true || was == false) {
        // Lock off, or just switched on after authenticating in Settings.
        if (_locked) setState(() => _locked = false);
      }
    });
    final enabled = ref.watch(appLockEnabledProvider).value;
    final locked = enabled == true && _locked;
    final cover = enabled == null || locked || _obscured;
    return Stack(
      children: [
        // While covered, nothing underneath is readable or actionable by a
        // screen reader either.
        ExcludeSemantics(excluding: cover, child: widget.child),
        if (cover) Positioned.fill(child: BlockSemantics(child: _Cover(showUnlock: locked && !_obscured, onUnlock: _unlock))),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.showUnlock, required this.onUnlock});
  final bool showUnlock;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return SizedBox.expand(
      child: ColoredBox(
        color: c.canvas,
        child: SafeArea(
          child: Center(
            child: showUnlock
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandMark(size: 72),
                      const SizedBox(height: EpSpace.lg),
                      Text(context.l10n.lockTitle, style: EpType.title(context, size: 22)),
                      const SizedBox(height: EpSpace.xl),
                      EpButton(label: context.l10n.lockUnlock, onPressed: onUnlock),
                    ],
                  )
                : Wordmark(name: context.l10n.appName, size: 24),
          ),
        ),
      ),
    );
  }
}
