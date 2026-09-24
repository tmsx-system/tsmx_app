import 'package:flutter/material.dart';

class AppNavigator {
  AppNavigator._();

  static final key = GlobalKey<NavigatorState>();

  static BuildContext? get context => key.currentContext;
}
