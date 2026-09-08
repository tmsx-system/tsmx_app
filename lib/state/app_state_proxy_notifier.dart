import 'package:flutter/foundation.dart';

import 'app_state.dart';

abstract class AppStateProxyNotifier extends ChangeNotifier {
  AppStateProxyNotifier({required this.appState});

  AppState appState;
  List<Object?> _lastWatchedValues = const [];
  bool _isWatching = false;

  @protected
  List<Object?> get watchFields;

  @protected
  void startWatchingAppState() {
    if (_isWatching) return;
    _lastWatchedValues = List<Object?>.from(watchFields);
    appState.addListener(_handleAppStateChanged);
    _isWatching = true;
  }

  void updateAppState(AppState value) {
    if (identical(appState, value)) return;
    if (_isWatching) {
      appState.removeListener(_handleAppStateChanged);
    }
    appState = value;
    _lastWatchedValues = List<Object?>.from(watchFields);
    if (_isWatching) {
      appState.addListener(_handleAppStateChanged);
    }
    notifyListeners();
  }

  void _handleAppStateChanged() {
    final next = watchFields;
    if (_sameWatchedValues(_lastWatchedValues, next)) return;
    _lastWatchedValues = List<Object?>.from(next);
    notifyListeners();
  }

  bool _sameWatchedValues(List<Object?> previous, List<Object?> next) {
    if (previous.length != next.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (!identical(previous[i], next[i]) && previous[i] != next[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    if (_isWatching) {
      appState.removeListener(_handleAppStateChanged);
    }
    super.dispose();
  }
}
