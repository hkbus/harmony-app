import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, AbilityConstant, common, Want } from '@kit.AbilityKit';
import NotificationManager from '@ohos.notificationManager';
import { wantAgent, WantAgent } from "@kit.AbilityKit"
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { geoLocationManager } from "@kit.LocationKit"
import getDistance from '../utils';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from "@kit.ArkData";
import { window } from '@kit.ArkUI';

let atManager = abilityAccessCtrl.createAtManager();

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  dialogController: CustomDialogController | null = null;
  uiContext: UIContext = this.getUIContext();
  context: Context = getContext(this);
  bridger: HarmonyBridger = new HarmonyBridger(this.uiContext, this.context);

  aboutToAppear(): void {
    try {
      webview.WebviewController.setWebDebuggingAccess(true);
    } catch (error) {
      console.error(`ErrorCode: ${(error as BusinessError).code},  Message: ${(error as BusinessError).message}`);
    }
  }

  build() {
    Column() {
      Stack() {
        Web({
          src: 'https://hkbus.app',
          controller: this.controller,
        })
          .onSslErrorEvent(event => {
            event.handler.handleConfirm();
          })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageBegin(() => {
            this.controller.setNetworkAvailable(true)
          })
          .geolocationAccess(true)
          .onGeolocationShow((event) => {
            let context: Context | undefined = this.uiContext.getHostContext() as common.UIAbilityContext;
            atManager.requestPermissionsFromUser(context,
              ["ohos.permission.APPROXIMATELY_LOCATION", "ohos.permission.LOCATION"]).then((data) => {
              console.info('data:' + JSON.stringify(data));
              console.info('data permissions:' + data.permissions);
              console.info('data authResults:' + data.authResults);
              if (data.authResults[0] === 0 && data.authResults[1] === 0) {
                event.geolocation.invoke(event.origin, true, true)
              } else {
                event.geolocation.invoke(event.origin, false, false)
              }
            }).catch((error: BusinessError) => {
              console.error(`Failed to request permissions from user. Code is ${error.code}, message is ${error.message}`);
            })
          })
          .javaScriptProxy({
            object: this.bridger,
            name: "harmonyBridger",
            methodList: ["share", "setAlarm", "unsetAlarm", "toggleAlarm", "openUrl", "setTheme"],
            controller: this.controller,
          })
          .runJavaScriptOnDocumentStart([
            {
              script: runFirst,
              scriptRules: ["*"]
            }
          ])
          .height('100%')
          .width('100%')
          .backgroundColor("#FF000000")
      }
    }
  }
}

class HarmonyBridger {
  uiContext: UIContext;
  context: Context;
  stopId: string | null;

  constructor(uiContext: UIContext, context: Context) {
    this.uiContext = uiContext;
    this.context = context;
    this.stopId = null;
  }

  async openUrl (url: string) {
    console.log(url)
    let context = this.uiContext.getHostContext() as common.UIAbilityContext;
    context.openLink(url, {
      appLinkingOnly: false,
      parameters: {},
    })
  }

  async toggleAlarm(stopId: string, location: StopLocation): Promise<string> {
    let isEnabled = await NotificationManager.isNotificationEnabled()
    if (!isEnabled) {
      await NotificationManager.requestEnableNotification()
    }
    if ( !(await NotificationManager.isNotificationEnabled()) ) {
      return Promise.resolve("");
    }
    const basicLocationPermissionGranted = await atManager.requestPermissionsFromUser(
      this.context, ["ohos.permission.APPROXIMATELY_LOCATION", "ohos.permission.LOCATION"]
    )
      .then((data) => {
        return data.authResults[0] === 0 && data.authResults[1] === 0;
      }).catch(() => {
        return false
      })

    if (!basicLocationPermissionGranted) {
      return Promise.resolve("");
    }
    const backgroundLocationPermissionGranted = await atManager.requestPermissionOnSetting(
      this.context, ["ohos.permission.LOCATION_IN_BACKGROUND"]
    )
      .then((data) => {
        return data[0] === 0
      }).catch((err: BusinessError) => {
        return err.code === 12100011 // Permission already granted
      })

    if (!backgroundLocationPermissionGranted) {
      return Promise.resolve("");
    }

    if (this.stopId !== stopId) {
      await this.unsetAlarm();
      this.stopId = null;
    }
    if (!this.stopId) {
      this.stopId = stopId;
      await this.setAlarm(location.lat, location.lng);
      return Promise.resolve(stopId)
    }
    this.stopId = null;
    await this.unsetAlarm();
    return Promise.resolve("");
  }

  async setAlarm(lat: number, lng: number): Promise<void> {
    let locationRequest: geoLocationManager.ContinuousLocationRequest = {
      'interval': 1,
      'locationScenario': geoLocationManager.UserActivityScenario.TRANSPORT
    }
    let locationCallback = (location: geoLocationManager.Location): void => {
      const distance = getDistance(location, { latitude: lat, longitude: lng });
      if (distance <= 500) {
        geoLocationManager.off("locationChange", locationCallback);
        NotificationManager.publish({
          id: Date.now(),
          content: {
            notificationContentType: NotificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: {
              title: '到站提示',
              text: `快將到站了 (${distance}m)`,
            }
          },
          notificationSlotType: NotificationManager.SlotType.SERVICE_INFORMATION,
        }, (err) => {
          if (err) {
            console.error(`[ANS] failed to publish, error[${err}]`);
            return;
          }
          console.info(`[ANS] publish success`)
        })
        this.unsetAlarm();
      }
    }
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "app.hkbus.huawei",
          abilityName: "MainAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    return wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.LOCATION, wantAgentObj
      ).then(() => {
        console.info(`Succeeded in operationing startBackgroundRunning`);
        try {
          geoLocationManager.on("locationChange", locationRequest, locationCallback);
        } catch (err) {
          console.error("errCode: " + JSON.stringify(err))
        }
      }).catch((err: BusinessError) => {
        console.error(`Failed to operation startBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
      });
    });
  }

  unsetAlarm(): Promise<void> {
    return backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      console.info(`Succeeded in operationing stopBackgroundRunning`);
    }).catch((err: BusinessError) => {
      console.error(`Failed to operation stopBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
    });
  }

  share(data: HkbusShareData): Promise<void> {
    let shareController = new systemShare.ShareController(new systemShare.SharedData({
      utd: utd.UniformDataType.HYPERLINK,
      title: data.title,
      description: "",
      content: data.url,
    }));
    shareController.show(this.context as common.UIAbilityContext, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE,
    });
    return Promise.resolve();
  }

  setTheme(theme: "light" | "dark") {
    let windowClass = AppStorage.get<window.Window>('windowClass') as window.Window;
    windowClass.setWindowSystemBarProperties({
      statusBarContentColor: theme === "light" ? "#FF000000" : "#FFFFFFFF"
    });
  }
}

interface StopLocation {
  lat: number,
  lng: number,
}

interface HkbusShareData {
  title: string,
  url: string,
};

const runFirst = `
    window.stopAlarm = true;
    window.harmonyShare = true;

    if (navigator.share == null) {
      navigator.share = (param) => {
         return harmonyBridger.share(param)
      };
    };

    window.systemColorSchemeCallbacks = [];
    window.systemColorScheme = new Proxy(
      { value: "light" },
      {
        set(target, property, value) {
          const result = Reflect.set(target, property, value);
          if (result) {
            window.systemColorSchemeCallbacks.forEach((callback) =>
              callback(value)
            );
          } else {
            console.error(
              "Failed to set window.systemColorScheme.",
              property,
              "to",
              value
            );
          }
          return result;
        },
      }
    );

    true; // note: this is required, or you'll sometimes get silent failures
`
