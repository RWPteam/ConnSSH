import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';

  Future<AppSettings> getSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsString = prefs.getString(_settingsKey);
      
      if (settingsString != null) {
        final settingsMap = Map<String, dynamic>.from(
          (settingsString.split('|').fold<Map<String, String>>({}, (map, item) {
            final parts = item.split(':');
            if (parts.length == 2) {
              map[parts[0]] = parts[1];
            }
            return map;
          }))
        );

        if (settingsMap.containsKey('isFirstRun')) {
          settingsMap['isFirstRun'] = settingsMap['isFirstRun'] == 'true';
        }
        
        return AppSettings.fromMap(settingsMap);
      }
    } catch (e) {
      debugPrint('读取设置失败: $e');
    }
    
    return AppSettings.defaults;
  }//从设置模型中获取数据

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsMap = settings.toMap();
      final settingsString = settingsMap.entries
          .where((entry) => entry.value != null)
          .map((entry) => '${entry.key}:${entry.value}')
          .join('|');
      await prefs.setString(_settingsKey, settingsString);
    } catch (e) {
      debugPrint('保存设置失败: $e');
      throw Exception('保存设置失败: $e');
    }
  }//将设置写入sharedpreferences

  Future<void> markAsNotFirstRun() async {
    try {
      final currentSettings = await getSettings();
      final updatedSettings = currentSettings.copyWith(isFirstRun: false);
      await saveSettings(updatedSettings);
    } catch (e) {
      debugPrint('标记为非第一次运行失败: $e');
      throw Exception('标记为非第一次运行失败: $e');
    }
  }//标记是否第一次运行，据此判断是否需要展示帮助

  static Future<String?> getPlatformDefaultDownloadPath() async {
    if (Platform.isAndroid) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloadDir = Directory('${externalDir.path}/Download');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir.path;
      }
    }
    
    return null;
  }//尝试获取安卓设备的特定目录，防止获取出错导致无法下载
}