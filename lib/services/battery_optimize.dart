import 'dart:io';
import 'package:flutter/material.dart';
import 'package:battery_optimization_permission/battery_optimization_permission.dart';

class BatteryHelper {
  static Future<bool> requestBatteryOptimizationPermission(
    BuildContext context,
  ) async {
    if (!Platform.isAndroid) return true;

    final isWhitelisted =
        await BatteryOptimizationPermission.isIgnoringBatteryOptimizations();

    if (isWhitelisted) {
      return true;
    }

    final success = await BatteryOptimizationPermission.ensureBatteryWhitelist(
      tryOemScreens: true,
      openSettingsFallbacks: true,
    );

    if (success) {
      return true;
    } else {
      return false;
    }
  }

  static Future<void> openOemAutoStartSettings() async {
    if (!Platform.isAndroid) return;

    final opened =
        await BatteryOptimizationPermission.openOemAutoStartSettings();
    if (!opened) {}
  }
}
