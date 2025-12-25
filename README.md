# ConnSSH  
A lightweight & cross-platform SSH/SFTP client built with Flutter.
一个基于Flutter的，轻量、跨平台的SSH/SFTP工具

### 特性
- 完整 SSH 终端（快捷键、终端主题、多会话）
- 完整 SFTP：批量文件操作，支持自定义默认访问目录
- 支持telnet：自动登录、多编码支持
- 响应式布局：多尺寸设备自适应
- 跨平台：Android / Windows / iOS / MacOS / HarmonyOS
- 支持私钥 / 密码 认证

### 截图
| 手机端SSH | 手机端SFTP | 平板端SFTP |
|-----------------|--------------|--------------|
| ![手机端SSH](docs/preview/ssh.jpg) | ![手机端SFTP](docs/preview/sftp.png) | ![平板端SFTP](docs/preview/sftp_pad.jpg) |

### 下载
| 平台 | 下载 | 备注 |
|------|------|------|
| Android | [APK](https://github.com/RWPteam/ConnSSH/releases/download/1.2.1/ConnSSH_1.2.1.apk) | arm64 |
| Windows | [exe](https://github.com/RWPteam/ConnSSH/releases/download/1.2.1/ConnSSH.1.2.1.Installer.exe) | 仅支持64位设备 |
| OHOS | [app](https://github.com/RWPteam/ConnSSH/releases/download/1.2.1/ConnSSH_1.2.1.app.zip) | 华为手机、平板用户需要从AppGallery下载 |
| OHOS | [AppGallery](https://appgallery.huawei.com/app/detail?id=com.samuioto.connecter&channelId=SHARE&source=appshare) | 已上架至华为应用市场，欢迎体验


### 构建&打包
* 需注意，本项目使用了修改过的[xterm.dart](https://github.com/samu1oto/xterm.dart)以添加快捷操作栏等功能
* 本项目使用了[openharmony-tpc/flutter_flutter](https://gitcode.com/openharmony-tpc/flutter_flutter/tree/br_3.22.0-ohos-1.0.4)而非正常版本的flutter，不保证正常版本下可用

```bash
# 源码运行（Flutter ≥ 3.22）
git clone https://github.com/RWPteam/connssh.git
cd connssh
flutter pub get
flutter run -d <device_id>
```

```bash
# Android
flutter build apk #--split-per-abi(Recommend)
# Windows
flutter build windows
# HarmonyOS NEXT
flutter build app
```
### ToDo
已迁移至 [GitHub Issues](https://github.com/RWPteam/ConnSSH) 

### 开源协议
BSD 3-Clause © 2025 RWPteam

### 感谢
- [xterm.dart](https://github.com/TerminalStudio/xterm.dart) – terminal UI
- [dartssh2](https://github.com/TerminalStudio/dartssh2) – SSH/SFTP engine
