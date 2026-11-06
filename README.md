# herdr-windows-offline

Herdr（herdr-app + herdr-core）**Windows x64 完全離線安裝包**。

本 repo 直接收錄官方 Windows 版的**解壓後原始檔案**（未修改任何位元組），clone 或整個資料夾帶到目標電腦後即可安裝，安裝過程**不需要網路**、**不需要系統管理員權限**、不需要 Git LFS。

與 Linux 版離線包（herdr-app-offline）是不同的 repo。

| 元件 | 版本 | 官方來源 | 官方 SHA256 |
|---|---|---|---|
| herdr-app | **0.1.13** | https://releases.herdr.dev/app/0.1.13/herdr-app-windows-x86_64.tar.gz | `72cb26f92a6b77e1125fecd2b18f87cc69a18c2da766a8ed8a5bcbd7b16c6012` |
| herdr-core | **0.1.18** | https://releases.herdr.dev/core/0.1.18/herdr-core-windows-x86_64.zip | `2e54e0b1dcbd652a7e89b14c588178f8241b9732fdc4e5f2b27208829b0bfbbc` |

版本與雜湊取自官方清單 https://releases.herdr.dev/app/latest.json 、 https://releases.herdr.dev/core/latest.json （打包當時的副本放在 `windows-x86_64/app-latest.json`、`windows-x86_64/core-latest.json`）。

## 支援環境

- **Windows 10 1803（build 17134）以上 x64**、Windows 11 x64（與官方安裝程式要求相同）。
- Windows PowerShell 5.1（Windows 內建）或 PowerShell 7 皆可。
- **不支援**：32 位元 Windows、ARM64 Windows（官方目前只提供 x64 版）、Windows 10 1803 之前的版本。

## 目錄結構

```
README.md
install.ps1                     # 離線安裝（PowerShell 5.1+）
uninstall.ps1                   # 安全移除
SHA256SUMS                      # windows-x86_64/ 下每個檔案的 SHA256
tools/herdr-offline-common.ps1  # install / uninstall 共用函式
tests/                          # 可在 Linux 執行的檢查（見「測試」）
windows-x86_64/
  herdr-app/                    # 官方 tar.gz 解壓內容：herdr-app.exe、herdr-app.svg、LICENSE、THIRD-PARTY-NOTICES
  herdr-core/                   # 官方 zip 解壓內容：herdr-core.exe、conpty/、LICENSE、THIRD-PARTY-NOTICES/
  app-latest.json               # 官方 app 清單（打包時）
  core-latest.json              # 官方 core 清單（打包時）
  official-archives.sha256      # 官方原始壓縮檔的 SHA256
```

所有檔案都小於 GitHub 單檔 100 MiB 上限（最大的 `herdr-app.exe` 約 60 MiB），因此**沒有分割檔**，也不需要合併步驟。

## 取得安裝包（在有網路的電腦上）

二擇一：

1. **git clone**（建議，clone 下來的檔案不會帶「網際網路下載」標記）：
   ```powershell
   git clone -b feat/windows-x64-offline-bundle https://github.com/z9905080/herdr-windows-offline.git
   ```
2. **下載 Release 的 ZIP**：到 [Releases](https://github.com/z9905080/herdr-windows-offline/releases) 下載
   `herdr-windows-offline-0.1.13-core0.1.18.zip`，並用同一頁的 `SHA256SUMS` 核對雜湊（見下方「驗證雜湊」）。

接著把**整個資料夾**（或 ZIP）用隨身碟、內網分享等方式帶到目標電腦。不要只複製 `install.ps1`，它需要旁邊的 `windows-x86_64\` 與 `SHA256SUMS`。

## 安裝

在目標電腦開啟 PowerShell（**一般使用者即可，不必「以系統管理員身分執行」**），切到安裝包資料夾：

```powershell
cd C:\path\to\herdr-windows-offline

# 先預覽會做哪些變更（不會實際寫入任何東西）
powershell -NoProfile -File .\install.ps1 -WhatIf

# 正式安裝
powershell -NoProfile -File .\install.ps1
```

安裝程式會：

1. 先用 `SHA256SUMS` 驗證 `windows-x86_64\` 內所有檔案，任何檔案缺漏或損毀就中止，不做任何變更。
2. 將 herdr-app 複製到 `%LOCALAPPDATA%\Programs\herdr-app`（與官方安裝位置相同）。
3. 建立開始功能表捷徑「Herdr」。
4. 將 herdr-core 複製到 `%LOCALAPPDATA%\Programs\herdr-core`（`herdr-core.exe` 與 `conpty\`），若系統上還沒有 `hc` 指令，會建立 `hc.exe`（指向 herdr-core.exe 的 hard link）。因此**第一次開啟 Herdr 時不需要再上網下載 core**。
5. 將上述兩個資料夾加入**使用者** PATH（只新增，不改動其他項目；`%USERPROFILE%` 等變數保持未展開的原樣，與官方做法相同）。新開的終端機視窗才會看到新的 PATH。
6. 在 `%LOCALAPPDATA%\herdr-windows-offline\install-state.json` 記錄「這次安裝新增了什麼」，供 `uninstall.ps1` 只移除自己加的東西。

可選參數：

| 參數 | 作用 |
|---|---|
| `-WhatIf` | 只顯示將執行的動作，不做任何變更 |
| `-SkipCore` | 不安裝/不更新 herdr-core |
| `-NoShortcut` | 不建立開始功能表捷徑 |
| `-NoPath` | 不修改使用者 PATH |

安裝完成後，從開始功能表開啟 **Herdr**，或在新的終端機執行 `herdr-app`。

### 重新安裝 / 升級

再次執行 `install.ps1`（例如換成新版安裝包）即可，行為比照官方安裝程式：

- **herdr-app**：新版本先複製到 `herdr-app.new`，再把舊資料夾改名為 `herdr-app.old`、新資料夾就位，最後刪除舊資料夾。若 Herdr 仍在執行導致無法替換，會提示先關閉 Herdr 再執行一次。
- **herdr-core**：
  - 尚未安裝 → 直接安裝。
  - 已安裝但**比安裝包舊** → 以官方的「計畫式更新」`herdr-core update --from <新檔>` 替換，**正在執行的終端機不會中斷**。
  - 已安裝且版本**相同或更新**（例如 app 已在線上自動更新過）→ 保持不動。
  - 安裝在其他位置（PATH 上找得到 `herdr-core`）→ 視為其他安裝，不會覆蓋。
- 使用者設定與資料（`%APPDATA%`、`%LOCALAPPDATA%` 下的 Herdr 設定）**完全不會碰**。

## 移除

```powershell
cd C:\path\to\herdr-windows-offline
powershell -NoProfile -File .\uninstall.ps1 -WhatIf   # 預覽
powershell -NoProfile -File .\uninstall.ps1
```

`uninstall.ps1` 依安裝紀錄只移除本安裝包建立的項目：

- `%LOCALAPPDATA%\Programs\herdr-app`（含殘留的 `.old`/`.new`）。
- 開始功能表「Herdr」捷徑（僅當它指向上述資料夾）。
- `%LOCALAPPDATA%\Programs\herdr-core`：**只有在當初是由本安裝包新裝的情況才移除**；原本就存在的 core 保留。
- 安裝時新增的 PATH 項目；其他 PATH 項目不變。

不會移除：本安裝包資料夾、Herdr 的使用者設定與資料、其他方式安裝的 Herdr。

| 參數 | 作用 |
|---|---|
| `-WhatIf` | 只預覽 |
| `-KeepCore` | 保留 herdr-core（即使是本安裝包裝的） |
| `-RemoveCore` | 連非本安裝包安裝的 herdr-core 也移除 |
| `-Force` | 沒有安裝紀錄時，仍移除 `herdr-app` 資料夾與其 PATH 項目 |

若 Herdr 或 herdr-core 仍在執行，移除程式會停止並提示，不會只刪一半。herdr-core 在背景維持你的終端機工作階段，移除前請先結束這些終端機，或使用 `-KeepCore`。

## 離線與需要網路的功能

| 功能 | 離線可用 |
|---|---|
| 安裝 / 升級 / 移除（本安裝包） | ✅ 完全離線 |
| 開啟 Herdr、在本機開終端機、herdr-core / `hc` 本機功能 | ✅ core 已預先安裝，不需下載 |
| Herdr / herdr-core 的線上更新（官方說明 app 會負責讓 core 保持最新） | ❌ 需要連線到 releases.herdr.dev；離線環境請改用新版安裝包重新執行 `install.ps1` |
| 連線到其他機器（例如 `hc machine add`）| 需要能連到那台機器的網路 |
| 在終端機裡執行、需要雲端 API 的程式或 coding agent | 依該程式本身而定，通常需要網路 |

## 驗證雜湊

**驗證安裝包內容**（`install.ps1` 每次都會自動驗證；也可手動）：

```powershell
# PowerShell：比對單一檔案
(Get-FileHash .\windows-x86_64\herdr-app\herdr-app.exe -Algorithm SHA256).Hash.ToLower()
Select-String herdr-app.exe .\SHA256SUMS
```

```bash
# Git Bash / Linux / macOS：一次驗證全部
sha256sum -c SHA256SUMS
```

**驗證官方原始壓縮檔**（Release 附件中的 `herdr-app-windows-x86_64.tar.gz`、`herdr-core-windows-x86_64.zip`）：雜湊應與上方表格、`windows-x86_64/official-archives.sha256`，以及官方 `latest.json` 的 `windows-x86_64.sha256` 完全一致。

**驗證 Release ZIP**：與 Release 頁面的 `SHA256SUMS` 比對：

```powershell
(Get-FileHash .\herdr-windows-offline-0.1.13-core0.1.18.zip -Algorithm SHA256).Hash.ToLower()
```

## PowerShell 執行原則（ExecutionPolicy）注意事項

Windows 用戶端預設的執行原則可能不允許執行本機 `.ps1` 腳本；從網路下載的 ZIP 解壓出的腳本，也可能被 Windows 視為「來自網際網路」。

- 先用 `Get-ExecutionPolicy -List` 查看目前設定。
- **公司或學校管理的電腦**：若 `MachinePolicy` / `UserPolicy` 有設定值，代表由群組原則（GPO）控管。請**向 IT 部門申請核准**執行本安裝包（可提供本 README 與 `SHA256SUMS` 供審查），**不要嘗試繞過**。
- **個人電腦**：Microsoft 文件建議用戶端使用 `RemoteSigned`，可只對目前使用者設定：
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
  在此原則下，git clone 下來的腳本可直接執行；若是由瀏覽器下載的 ZIP，請先核對 ZIP 雜湊，確認來源可信後，再依你的使用政策決定是否於檔案「內容」中解除封鎖。
- 本專案**不建議**使用 `-ExecutionPolicy Bypass`、停用防毒或其他安全機制。本 repo 只是把官方檔案整理成可離線安裝的形式，**不是用來規避企業管控的工具**。

另外，Windows SmartScreen 或防毒軟體可能對新下載的執行檔顯示提示，這是正常的安全機制；請先核對雜湊，再依組織政策處理。本安裝程式不會移除檔案的下載標記，也不會變更任何安全設定。

## 大小

| 項目 | 大小 |
|---|---|
| 官方 app 壓縮檔（tar.gz） | 約 23.8 MB |
| 官方 core 壓縮檔（zip） | 約 3.7 MB |
| `windows-x86_64\`（解壓後內容） | 約 72 MB |
| 安裝後：herdr-app | 約 64 MB |
| 安裝後：herdr-core | 約 11 MB |

## 限制

- 只有 Windows x64。ARM64 Windows 不支援（官方也尚未提供）。
- 安裝包內的版本固定為上表版本；離線環境不會自動更新，要升級請取得新版安裝包。
- 只做「目前使用者」安裝（`%LOCALAPPDATA%`），不提供全機安裝。
- 若官方日後調整安裝位置或安裝流程，本腳本需跟著更新。
- 本 repo 的腳本**尚未在實體 Windows 上做 GUI 端對端測試**（見下方「測試」）。

## 測試

在 Linux 上可執行（需要 `sha256sum`、`python3`，有 `pwsh` 時另做 PowerShell 檢查）：

```bash
tests/run-linux-tests.sh                       # 驗證 SHA256SUMS、官方清單、檔案大小、PowerShell 語法與單元測試
tests/run-linux-tests.sh /path/to/archives     # 另外把官方壓縮檔重新解壓，逐位元組比對 repo 內容
```

內容包含：PowerShell 語法解析、ASCII 檢查（Windows PowerShell 5.1 編碼相容）、PSScriptAnalyzer 的 PowerShell 5.1 語法相容性檢查（若已安裝）、PATH 增刪（保留 `%變數%`）、SHA256 驗證（含竄改/缺檔偵測）、版本比較、資料夾複製合併、安裝紀錄讀寫。

**尚未測試**：在真實 Windows 上執行 `install.ps1` / `uninstall.ps1`（登錄檔 PATH、開始功能表捷徑、hard link、herdr-core 計畫式更新、Herdr GUI 啟動）。歡迎在 Windows 上試用並回報。

## 授權

herdr-app、herdr-core 以 Apache License 2.0 授權（見各自資料夾中的 `LICENSE`），第三方元件授權見 `THIRD-PARTY-NOTICES`；ConPTY（`conpty.dll`、`OpenConsole.exe`）為 Microsoft 元件，授權見 `windows-x86_64/herdr-core/THIRD-PARTY-NOTICES/`。本 repo 的打包腳本僅為整理與安裝之用。
