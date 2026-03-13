import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { AbilityConstant, Want, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MethodChannel, MethodCall, MethodResult, MethodCallHandler } from '@ohos/flutter_ohos'; // 确保导入 MethodCallHandler
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'EntryAbility';
const CHANNEL_NAME = 'com.samuioto.connecter/background_task';

export default class EntryAbility extends FlutterAbility {
  private methodChannel: MethodChannel | null = null;
  private notificationId: number = 0;
  private isBackgroundRunning: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'EntryAbility onCreate');
    super.onCreate(want, launchParam);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    hilog.info(0x0000, TAG, 'configureFlutterEngine called');
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    this.setupMethodChannel(flutterEngine);
  }

  private setupMethodChannel(flutterEngine: FlutterEngine): void {
    try {
      const messenger = flutterEngine.dartExecutor.getBinaryMessenger();
      this.methodChannel = new MethodChannel(messenger, CHANNEL_NAME);

      const handler: MethodCallHandler = {
        onMethodCall: (call: MethodCall, result: MethodResult): void => {
          hilog.info(0x0000, TAG, `Method called: ${call.method}`);
          this.handleMethod(call, result);
        }
      };

      this.methodChannel.setMethodCallHandler(handler);
      hilog.info(0x0000, TAG, `Channel ${CHANNEL_NAME} registered successfully`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to setup MethodChannel: ${(error as Error).message}`);
    }
  }

  private handleMethod(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'startBackgroundRunning':
        this.startContinuousTask();
        result.success({ success: true });
        break;

      case 'stopBackgroundRunning':
        this.stopContinuousTask();
        result.success({ success: true });
        break;

      case 'updateNotification':
        const titleArg: string | null = call.argument('title');
        const contentArg: string | null = call.argument('content');
        const title: string = titleArg ?? 'SSH 服务运行中';
        const content: string = contentArg ?? '保持后台连接';
        this.updateNotification(title, content);
        result.success({ success: true });
        break;

      default:
        result.notImplemented();
    }
  }

  private startContinuousTask(): void {
    if (this.isBackgroundRunning) {
      hilog.info(0x0000, TAG, 'Background task already running');
      return;
    }

    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "com.samuioto.connecter",
          abilityName: "EntryAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };

    try {
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        const bgModes: Array<string> = ["dataTransfer"];

        backgroundTaskManager.startBackgroundRunning(this.context, bgModes, wantAgentObj)
          .then((res: backgroundTaskManager.ContinuousTaskNotification) => {
            hilog.info(0x0000, TAG, 'startBackgroundRunning succeeded');
            this.notificationId = res.notificationId;
            this.isBackgroundRunning = true;
            this.updateNotification('SSH 服务运行中', '保持后台连接维持 SSH 会话');
          })
          .catch((error: BusinessError) => {
            hilog.error(0x0000, TAG, `startBackgroundRunning failed: ${error.code}, ${error.message}`);
            this.isBackgroundRunning = false;
          });
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `getWantAgent error: ${(error as Error).message}`);
    }
  }

  private stopContinuousTask(): void {
    if (!this.isBackgroundRunning) return;

    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      hilog.info(0x0000, TAG, 'stopBackgroundRunning succeeded');
      this.isBackgroundRunning = false;
      this.notificationId = 0;
    }).catch((err: BusinessError) => {
      hilog.error(0x0000, TAG, `stopBackgroundRunning failed: ${err.message}`);
    });
  }

  private updateNotification(title: string, content: string): void {
    if (!this.isBackgroundRunning || this.notificationId === 0) return;

    const request: notificationManager.NotificationRequest = {
      id: this.notificationId,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: {
          typeCode: 8,
          title: title,
          text: content,
        }
      },
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
    };

    notificationManager.publish(request).catch((err: BusinessError) => {
      hilog.error(0x0000, TAG, `updateNotification failed: ${err.message}`);
    });
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onDestroy');
    this.stopContinuousTask();
    // 使用 undefined 替代 null as any
    this.methodChannel?.setMethodCallHandler(undefined);
    super.onDestroy();
  }
}