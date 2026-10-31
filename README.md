# Far Far West · 作弊修改 Mod（FFW_Cheat）

给《遥遥西土 / Far Far West》做的 UE4SS Lua 作弊模组。所有功能都调用游戏**自己的**蓝图属性与函数，
不碰内存地址，只要官方不改蓝图变量名，游戏更新后依然可用。

- 游戏版本：UE 5.8 自定义引擎（Canyon），Steam 抢先体验版
- 加载器：UE4SS 实验版 + 官方仓库里的 `Far Far West` 5.8 签名配置
- 模组位置：`...\FarFarWest\Binaries\Win64\ue4ss\Mods\FFW_Cheat\`

> **2026-10-31 更新说明**
> 那次崩溃（`UE4SS.dll` 内部 `ACCESS_VIOLATION`）来自"引擎飞行"实验代码——`SetMovementMode`
> 加 40 ms 高频重压循环，已彻底删除。
> 游戏自带的 freecam（`F12` / `ffw freecam`）和 `ffw menu` 保留：只调用**零参数**蓝图函数，
> 属于实机验证过能用的部分。

---

## 一、功能与按键

| 按键 | 功能 | 实现方式 |
|---|---|---|
| `F1` | **无敌** | `BP_PlayerState_C.invincible = true`，并持续把血量/护盾补满 |
| `F2` | **无限弹药** | 定期调用游戏自带的 `F_RefillAllAmmo_OwningClient` |
| `F3` | **无限跳跃 / 冲刺** | `jumpsLeft` / `currentDashLeft` / `maxDash` = 9 |
| `F4` | **加速** | `buffMoveSpeed +1.0`（约 2 倍速），再按一次恢复 |
| `F5` | **低重力** | `buffGravity -0.65`（约三分之一重力），再按一次恢复 |
| `F6` | **加金币** +10000 | `pickedUpGolds` + `F_UpdateGolds` |
| `F7` | **加灵魂** +10000 | `pickedUpSouls` + `F_UpdateSouls` |
| `F8` | **加铀矿** +250 | `pickedUpUranium` + `F_UpdateUranium` |
| `F9` / `Insert` | **回满血与护盾** | 写入满值 |
| `F10` | **清空附近敌人** | 遍历 `BP_Enemy_C` 调 `F_DestroyEnemy`（每次最多 200 个） |
| `F11` | **地图全开** | `mapRevealed = true` |
| `F12` | **自由视角（freecam）** | `F_SpawnFreecam_Server` / `F_RemoveFreecam_Server`，生成游戏自己的 `BP_Freecam_C` 飞行 Pawn；再按一次回到角色 |
| `Delete` | **补满弹药**（一次） | 同 F2 |

> 想要控制台的文字菜单：先按 `F12` 进 freecam，再在控制台敲 `ffw menu`，会把官方调试面板
> （`UI_CheatMenu`）拉起来。这是实测可用的路径——菜单宿主 `BP_Manager_Cheats_C` 平时不在关卡里，
> 走 `BP_PlayerController_C.F_OpenCheatsMenu()` 这个零参入口才起得来。
>
> **菜单已汉化**：模组启动 12 秒后会把 `UI_CheatMenu` 的控件模板整体换成中文（日志会打印
> `ZH: template labels translated: 57`），打开菜单时还会对实例再补一遍。41 个按钮 + 16 个
> 分区标题全部覆盖；万一以后游戏更新出现新字串，日志会打印 `ZH missing: [...]`，把那一行发我即可。
> 也可以随时敲 `ffw zh` 手动重跑一次。

## 二、控制台命令

UE4SS 调试窗口随游戏启动（`CTRL+O` 显示/隐藏），也可以按 `~` 用游戏控制台：

```
ffw help                                  查看全部命令
ffw god | ammo | jump | speed | gravity   切换对应作弊
ffw freecam                               开/关自由视角（同 F12）
ffw menu                                  打开 / 关闭官方调试菜单（先开 freecam 更稳）
ffw zh                                    重新执行一次菜单汉化
ffw fix                                   恢复正常操控（退出 freecam + 交还键盘）
ffw gold [数量] | souls [数量] | uranium [数量]
ffw heal | kill | reveal
ffw status                                当前抓到的对象和数值
ffw diag                                  详细对象报告（排查用）
```

如果 UE4SS 的控制台执行的是 Lua 而不是游戏命令，用同名函数：

```lua
ffw("gold", 99999)
ffw("menu")
ffw("status")
```

## 三、安装

已经有 UE4SS（本机当前状态）：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

还没有 UE4SS：

1. 从 [UE4SS 发布页](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest) 下载
   **2025 年以后**的实验版（旧版 3.0.1 认不出 UE 5.8），解压到 `...\FarFarWest\Binaries\Win64\`，
   确认存在 `dwmapi.dll` 与 `ue4ss\UE4SS.dll`；
2. 再跑一次安装脚本，它会补上本模组自带的 `ue4ss-config`（5.8 签名 + 调好的 `UE4SS-settings.ini`）。

或者一步到位指向任意一份已解压的 UE4SS：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Ue4ssSource "D:\下载\UE4SS"
```

装完直接启动游戏，模组自动加载，不需要额外启动器或参数。

## 四、卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

只删 `FFW_Cheat` 目录，UE4SS 本体保留（别的模组还要用）。
彻底移除加载器：删掉 `Binaries\Win64\dwmapi.dll` 和 `Binaries\Win64\ue4ss` 目录。

## 五、崩溃 / 卡死怎么办

1. **先确认是不是模组引起的**：删掉 `ue4ss\Mods\FFW_Cheat`（或把里面的 `enabled.txt` 改名）再进游戏。
   不崩就是模组，崩就别用了。
2. 崩溃转储在 `...\FarFarWest\Binaries\Win64\ue4ss\`，文件名 `crash_*.dmp`，一个约 39 MB；
   同目录的 `UE4SS.log` 记录模组最后在做什么（本模组的日志都以 `[FFW_Cheat]` 开头）。
3. 高风险调用（引擎飞行、40 ms 循环、签名不明的 RPC）已经全部移除；保留的 freecam / menu
   只调用零参数函数。如果仍然崩，把 `crash_*.dmp` 和 `UE4SS.log` 发我，我按崩溃地址定位。
4. **关掉菜单后人物不能按键盘移动**：已修——关闭现在先走 `BP_Manager_Menu_C.F_CloseCheat()`
   （游戏自己的成对关闭入口），再执行 `restoreGameInput()`：`SetIgnoreMoveInput(false)`、
   `SetIgnoreLookInput(false)`、`SetPause(false)`、`bShowMouseCursor=false`。
   如果还遇到，敲 `ffw fix`；若当时仍在 freecam（相机在动、角色不动），按 `F12` 或 `ffw fix` 退出。

已确认的历史崩溃（全部落在 `UE4SS.dll` 内部 `ACCESS_VIOLATION`，不是游戏本体）：

| 时间 | 崩溃地址 | 触发 |
|---|---|---|
| 10-30 23:02 | `UE4SS.dll+0x2BE197` | 对已失效对象调用蓝图函数（我的诊断脚本） |
| 10-30 23:30 | `UE4SS.dll+0x2DB271` | 直接 `OpenLevel` 跳地图（我的测试） |
| 10-31 12:06 | `UE4SS.dll+0xC7D5E0` | 旧版引擎飞行（`SetMovementMode` + 40 ms 循环），已删除 |

## 六、注意事项

- **单人或自己当房主时效果最好。** 血量、金币是服务器权威数值，作为客机加入别人的房间会被同步回去，
  这是游戏机制，不是模组坏了。
- 游戏里有 `F_CheckIfPlayerIsLegit`、`isSuspicious` 这类校验，**别在公开联机房间里乱用**，
  也别拿改过的数据冲排行榜。
- 改钱之前建议先备份存档：`%LOCALAPPDATA%\FarFarWest\Saved\SaveGames\`
- 官方调试菜单（`UI_CheatMenu`）：**先按 `F12` 进 freecam，再敲 `ffw menu`**，实测可用。
  菜单宿主 `BP_Manager_Cheats_C` 平时不 placed 在关卡里，所以三条零参入口要依次试——
  实测生效的是第 2 条 `BP_Manager_Menu_C.F_OpenCheat()`（日志里 `menu step 2/3 ... called`，
  随后 `cheat menu is open`）。再敲一次 `ffw menu` 会调用 `UI_CheatMenu_C.F_Close()` 关掉。
- `F4` / `F5` 是给角色的 buff 字段加偏移量，手感可能偏夸张；改 `Scripts\main.lua` 顶部的
  `CONFIG.speedBuff` / `CONFIG.gravityBuff` 即可（0 等于原版）。

## 七、目录结构

```
FarFarWestCheatMod\
├─ install.ps1                  安装 / 卸载
├─ README.md                    本文件
├─ Mods\
│  └─ FFW_Cheat\
│     ├─ Scripts\main.lua       模组主体
│     └─ enabled.txt
├─ ue4ss-config\
│  ├─ UE4SS-settings.ini        5.8 专用加载器配置（调试控制台开）
│  └─ UE4SS_Signatures\         GNatives / ProcessLocalScriptFunction 签名
└─ tools\
   └─ FFW_Probe\                开发用：导出全部 UClass / 属性 / 函数名
```

## 八、实现说明

| 类 | 成员 | 类型 |
|---|---|---|
| `BP_Player_C` | `jumpsLeft` / `currentDashLeft` / `maxDash` | int |
| | `buffMoveSpeed` / `buffGravity` | float（加成值，0 = 原版） |
| `BP_PlayerState_C` | `invincible` | bool |
| | `playerHeal` / `playerMaxHeal` | float |
| | `F_RefillAllAmmo_OwningClient` / `F_UpdateSpeed` / `F_UpdateGravity` | 无参函数 |
| `AC_PlayerState_Shield_C` | `shieldPoints` / `shieldPointsMax` | float |
| `BP_GameState_C` | `pickedUpGolds` / `pickedUpSouls` / `pickedUpUranium` | int |
| | `mapRevealed` | bool |
| | `F_UpdateGolds` / `F_UpdateSouls` / `F_UpdateUranium` | 无参函数 |
| `BP_Enemy_C` | `F_DestroyEnemy` | 无参函数 |

**安全约定（改代码时请遵守）：**

1. 写属性前先 `GetPropertyValue` 读一次，按读到的 Lua 类型再写（`main.lua` 的 `setProp`）。
2. 只调用**零参数**、且实机验证过的蓝图函数；签名不明的函数一律不调。
3. 每次触碰对象前重新 `IsValid()`——`FindAllOf` 快照里的对象可能已经被销毁。
4. 后台循环不低于 250 ms，不要高频 `ExecuteInGameThread`。
5. Lua 的 `pcall` **拦不住**原生层访问违例，「多试几次参数」这种做法是危险的。
