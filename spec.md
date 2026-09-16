App Name: ThaiTalk

**Flutter + Azure Speech**

Flutter Android App；朗讀可選本機 TTS 或 Azure TTS，Azure Speech 負責錄音發音評分，Supabase 為選用的學習進度同步。

「單字/句字資料」 thai_practice_dataset.json

APIKEY: AZURE_APIKEY in .env
AZURE_URL=https://southeastasia.api.cognitive.microsoft.com/

don't commit .env

功能至少有：
[ 常用單字 ] (泰文/romanization/中文)
單字卡 / 測驗 / 發音 / 朗讀&評分

[ 日常句子 ] (泰文/romanization/中文)
情境句子 / 發音 / 朗讀&評分

其他依 專業語文學習 APP 進行設計
ICON 用 IMAGEGEN 產生

Support Android App


## 最新確認需求（2026-09-16）

- 僅支援 Android，不需要 iOS、桌面或網頁版。
- 設定頁只保留說話者「男／女」，選擇後儲存在手機，下次啟動保留，預設男。移除設定中的 Local／Azure TTS 選項。
- Local 使用已安裝的 Android 離線泰語語音；Azure TTS 與錄音發音評分直接透過 HTTPS 呼叫 Azure Speech，不使用自建語音後端。
- 建置時從本機 `.env` 讀取 Azure Speech Key，以可逆 XOR/base64 編碼內建 APK；使用者不需輸入 Key。原始 `.env` 不打包、不提交 Git。此編碼不保證防逆向擷取。
- 例句及情境句依說話者切換男女自稱、禮貌用語及對應拼音；顯示、複製、朗讀、評分使用同一版本。字典單字維持原義。
- Azure TTS 依性別選 Niwat 男聲或 Premwadee 女聲。本機 TTS 優先選可辨識性別的離線泰語聲音，否則使用可用的離線泰語聲音；設定頁不顯示這項限制說明。
- 泰文詞語间加空白供初學者閱讀；保留原始泰文作為語音輸入。
- 單字與句子提供複製到剪貼簿按鈕。
- Local／Azure TTS 使用各自的正常速度播放按鈕；移除慢速按鈕。Local 不讀寫音檔快取；Azure 依原始泰文、聲音與速度保存音檔快取（上限 64 MB），重複朗讀使用快取。
- 缺少離線泰語語音時提示到系統設定安裝；切換說話者或離開卡片時停止原本朗讀。
- Supabase 帳號／進度同步為選用；本機學習與 Azure 語音無須登入。
- 單字／句子頁只顯示篩選與練習入口，不列出個別內容卡片。
- 每次開始單字卡或測驗時，從目前篩選範圍隨機抽選 10 個並打亂順序；不足 10 個時使用全部，單輪不重複。左右切換維持該輪順序。
- 單字卡／測驗卡使用單一手機畫面的矩形卡面。單字卡直接顯示中文；測驗以中文選項作答。
- 卡片下方同一卡框內，圖示依序為「例句、Local TTS 播放、Azure TTS 播放、錄音練習」。例句按鈕只在單字卡顯示，不在句子卡或測驗顯示；卡面左右箭頭切換上／下一張。
- 單字例句顯示泰文、Romanization 及中文，可複製；底部依序為 Local TTS 播放、Azure TTS 播放、關閉按鈕，不提供錄音練習。
- 泰文字型使用隨 App 打包的 Noto Serif Thai。
- **本次 NO BUILD；只有使用者再次明確要求 build 時才建置 APK，平常修改只進行靜態分析與測試。**

## APK 體積與自行安裝

- 建置 helper 預設 Release、每個 CPU 架構獨立 APK（ARM64、ARM32、x86-64）；可選單一架構或 universal。
- 沒有 `android/key.properties` 時，Release 使用既有 debug key 簽章供直接安裝；有正式設定時沿用正式金鑰。
- Noto Sans TC 僅打包涵蓋介面與教材的裁切版，保留原始完整字型供重新產生；Noto Serif Thai 保留完整字型。
- 品牌資料只打包實際使用的圖片。仍遵守 NO BUILD，直到使用者再次要求建置。

## 教材更新

- 教材改名為 `thai_practice_dataset.json`（根目錄及 assets 副本），以 SHA-256 sidecar `thai_practice_dataset.json.sha256` 判定內容版本。
- 每次啟動檢查 `https://raw.githubusercontent.com/sibuzu/thaitalk/main/` 的 checksum；相同時不下載教材，不同時下載驗證後替換手機上的教材副本。
- 保留 APK 內建資料供首次使用與故障回退；斷網、逾時、校驗／格式錯誤或寫入失敗都不破壞舊資料。
- 教材筆數可變，首頁統計、每日一詞及測驗使用同一更新版本。收藏及進度仍以既有 ID 對應。
- 發布時用 `python3 scripts/update_dataset.py` 同步 assets 與 checksum，再 commit／push 到 GitHub main。此功能須先安裝含更新程式的 APK 才會生效。
