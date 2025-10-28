# connecter
A lightweight SSH connection tool based on flutter
# todo
* SFTP bug
> * 权限始终显示为未知
* 极端情况下的overflow
> * Problem: flutter3.22.1-ohos不兼容window_manager，无法限制窗口大小
> * Plan: 独立ohos分支
# harmonyos端迁移
* 初步完成，但疑似ohos和其他端的源代码无法兼容，待上述问题解决后在新的分支修复
* 问题：
1. 任何情况下的overflow
2. 无法读取/保存任何数据