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
  void handleWatchedFieldsChanged(List<Object?> previous, List<Object?> next) {}

  @protected
  bool didAuthScopeChange(
    List<Object?> previous,
    List<Object?> next, {
    required int authIndex,
    int? siteIndex,
    int? userIndex,
  }) {
    final isAuthenticated = next.length > authIndex && next[authIndex] == true;
    if (!isAuthenticated) return true;
    if (previous.isEmpty) return false;
    if (previous.length <= authIndex ||
        previous[authIndex] != next[authIndex]) {
      return true;
    }
    if (siteIndex != null &&
        previous.length > siteIndex &&
        next.length > siteIndex &&
        previous[siteIndex] != next[siteIndex]) {
      return true;
    }
    if (userIndex != null &&
        previous.length > userIndex &&
        next.length > userIndex &&
        previous[userIndex] != next[userIndex]) {
      return true;
    }
    return false;
  }

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
    final previous = _lastWatchedValues;
    _lastWatchedValues = List<Object?>.from(next);
    handleWatchedFieldsChanged(previous, next);
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
