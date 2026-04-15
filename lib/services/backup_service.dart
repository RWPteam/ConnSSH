import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt_package;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/backup_data_model.dart';
import '../services/storage_service.dart';
import '../services/setting_service.dart';
import 'package:crypto/crypto.dart' as crypto;

class BackupService {
  final StorageService _storageService;
  final SettingsService _settingsService;

  BackupService({
    required StorageService storageService,
    required SettingsService settingsService,
  }) : _storageService = storageService,
       _settingsService = settingsService;

  encrypt_package.Key _generateKey(String password) {
    final hash = crypto.sha256.convert(utf8.encode(password));
    return encrypt_package.Key(Uint8List.fromList(hash.bytes));
  }

  encrypt_package.IV _generateIV(String password) {
    final hash = crypto.sha1.convert(utf8.encode(password));
    return encrypt_package.IV(Uint8List.fromList(hash.bytes.sublist(0, 16)));
  }

  Future<BackupData> _collectBackupData() async {
    final connections = await _storageService.getConnections();
    final credentials = await _storageService.getCredentials();
    final recentConnections = await _storageService.getRecentConnections();
    final settings = await _settingsService.getSettings();
    final archiveGroups = await _storageService.getArchiveGroups();

    return BackupData(
      connections: connections,
      credentials: credentials,
      recentConnections: recentConnections,
      settings: settings,
      archiveGroups: archiveGroups,
      backupTime: DateTime.now(),
      version: '2.1.0',
    );
  }

  Future<String> backupData(String password) async {
    try {
      final backupData = await _collectBackupData();
      final jsonString = jsonEncode(backupData.toJson());

      final key = _generateKey(password);
      final iv = _generateIV(password);
      final encrypter = encrypt_package.Encrypter(
        encrypt_package.AES(key, mode: encrypt_package.AESMode.cbc),
      );
      final encrypted = encrypter.encrypt(jsonString, iv: iv);

      final dateStr = DateTime.now().toString().replaceAll(
        RegExp(r'[:\.]'),
        '-',
      );
      final fileName = 'backup-$dateStr.cntinfo';

      String savePath;

      if (Platform.isAndroid || Platform.isIOS) {
        final backupDirPath =
            await SettingsService.getPlatformDefaultBackupPath();
        final filePath = path.join(backupDirPath, fileName);
        final file = File(filePath);
        await file.writeAsBytes(encrypted.bytes);
        savePath = file.path;

        debugPrint('备份文件已保存到: $savePath');
      } else if (Platform.operatingSystem == 'ohos') {
        final appDocDir = await getApplicationDocumentsDirectory();
        final backupDir = Directory('${appDocDir.path}/Backups');
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }

        final tempSavePath = '${backupDir.path}/$fileName';
        final tempFile = File(tempSavePath);
        await tempFile.writeAsBytes(encrypted.bytes);
        final savedPath = await FilePicker.saveFile(
          dialogTitle: '保存备份文件',
          fileName: fileName,
          allowedExtensions: ['cntinfo'],
          initialDirectory: tempSavePath,
          bytes: encrypted.bytes,
        );

        if (savedPath != null && savedPath.isNotEmpty) {
          if (savedPath != tempSavePath) {
            try {
              final savedFile = File(savedPath);
              await savedFile.writeAsBytes(encrypted.bytes);
              await tempFile.delete();
              savePath = savedPath;
            } catch (e) {
              debugPrint('保存到用户选择位置失败: $e');
              savePath = tempSavePath;
            }
          } else {
            savePath = tempSavePath;
          }
        } else {
          final shouldKeep = await _showKeepTempFileDialog();
          if (shouldKeep) {
            savePath = tempSavePath;
          } else {
            await tempFile.delete();
            throw Exception('用户取消保存');
          }
        }
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        String? result = await FilePicker.saveFile(
          dialogTitle: '保存备份文件',
          fileName: fileName,
          allowedExtensions: ['cntinfo'],
          type: FileType.custom,
        );

        if (!result!.toLowerCase().endsWith('.cntinfo')) {
          result = '$result.cntinfo';
        }

        final file = File(result);
        await file.writeAsBytes(encrypted.bytes);
        savePath = result;
      } else {
        throw Exception('不支持的平台');
      }

      return savePath;
    } catch (e) {
      debugPrint('备份失败: $e');
      rethrow;
    }
  }

  Future<bool> _showKeepTempFileDialog() async {
    return false;
  }

  Future<BackupData> restoreData(String filePath, String password) async {
    try {
      Uint8List encryptedBytes;

      if ((Platform.isAndroid || Platform.isIOS) && filePath.isEmpty) {
        final backupDirPath =
            await SettingsService.getPlatformDefaultBackupPath();
        final backupDir = Directory(backupDirPath);

        if (!await backupDir.exists()) {
          throw Exception('备份目录不存在，请先进行备份');
        }

        final files = await backupDir
            .list()
            .where((entity) => entity.path.toLowerCase().endsWith('.cntinfo'))
            .map((entity) => entity.path)
            .toList();

        if (files.isEmpty) {
          throw Exception('备份目录中没有找到备份文件');
        }

        files.sort((a, b) => b.compareTo(a));
        filePath = files.first;

        debugPrint('使用最新备份文件: $filePath');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('备份文件不存在');
      }

      encryptedBytes = await file.readAsBytes();

      // 解密数据
      final key = _generateKey(password);
      final iv = _generateIV(password);
      final encrypter = encrypt_package.Encrypter(
        encrypt_package.AES(key, mode: encrypt_package.AESMode.cbc),
      );
      final encrypted = encrypt_package.Encrypted(encryptedBytes);
      final decryptedString = encrypter.decrypt(encrypted, iv: iv);

      // 解析JSON
      final Map<String, dynamic> jsonData = jsonDecode(decryptedString);
      return BackupData.fromJson(jsonData);
    } catch (e) {
      debugPrint('恢复失败: $e');
      if (e.toString().contains('Bad state: Unknown element type')) {
        throw Exception('密码错误或文件已损坏');
      }
      throw Exception('恢复失败: $e\n可能是密码错误或文件已损坏');
    }
  }

  Future<List<FileSystemEntity>> getBackupFiles() async {
    final backupDirPath = await SettingsService.getPlatformDefaultBackupPath();
    final backupDir = Directory(backupDirPath);
    if (!await backupDir.exists()) {
      return [];
    }
    final files = await backupDir
        .list()
        .where((entity) => entity.path.toLowerCase().endsWith('.cntinfo'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> applyRestoredData(BackupData backupData) async {
    try {
      // 恢复设置
      await _settingsService.saveSettings(backupData.settings);

      // 清空现有数据
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_connections');
      await prefs.remove('saved_credentials');
      await prefs.remove('recent_connections');
      await prefs.remove('archive_groups'); // 清空现有分组

      for (final group in backupData.archiveGroups) {
        await _storageService.saveArchiveGroup(group);
      }

      for (final connection in backupData.connections) {
        await _storageService.saveConnection(connection);
      }

      for (final credential in backupData.credentials) {
        await _storageService.saveCredential(credential);
      }

      final recentConnectionsJson = json.encode(
        backupData.recentConnections.map((c) => c.toJson()).toList(),
      );
      await prefs.setString('recent_connections', recentConnectionsJson);
    } catch (e) {
      debugPrint('应用恢复数据失败: $e');
      throw Exception('应用恢复数据失败: $e');
    }
  }
}
