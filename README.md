# ThaiTalk

Android 泰語學習 App，以 Flutter 製作。繁體中文介面、300 個常用單字、100 個男性情境句，預設 Azure 泰語男聲 Niwat。

## 安裝與使用

安裝 `build/app/outputs/flutter-apk/app-debug.apk` 後即可使用；**不需要自建後端，也不需要使用者輸入 API Key**。

目前 APK 是先前的 1.1.0 測試版本，尚未包含本次卡片介面與隨機練習修改。依使用者要求，僅在明確要求 **build** 時重新建置。

- 單字、拼音、中文及例句，泰文以詞語空白方便跟讀。
- 主題／程度篩選、搜尋、收藏、間隔複習、單字卡及四選一測驗。
- 單字／句子頁顯示篩選與練習入口。每次開始抽選最多 10 個不重複內容，出現順序也隨機。
- 手機單一卡面直接顯示單字中文；左右箭頭切卡，朗讀／發音練習使用同框圖示。測驗以中文選項作答。
- 單字例句可從圖示開啟查看、朗讀及複製，不需要錄音練習。
- 一鍵複製單字或句子到剪貼簿。
- Azure 正常／慢速男聲朗讀、錄音與發音準確度／流暢度／完整度評分。
- 64 MB 本機 TTS 持久快取：同文字／聲音／語速直接重用，重開 App 或離線也能播放已下載內容。
- 學習進度、每日目標、連續學習天數和 XP 自動保存在手機。

首次朗讀與每次發音評分需要網路；App 透過 HTTPS 直接呼叫 Azure。錄音最長 30 秒，只在送出評分時傳送，不會保存在學習紀錄或資料庫中。沒有設定 Azure Key 的一般開發建置仍可使用本機學習與已有音檔快取。

## 建置 Android APK

需要 Flutter 3.44+ / Dart 3.12+、Python 3、JDK 17 與 Android SDK。目前建置的 APK 最低為 Android 7.0（API 24）。

1. 在專案根目錄 `.env` 填入 Azure Speech 設定（現有檔案可直接使用）：

   ```dotenv
   AZURE_APIKEY=your-azure-speech-key
   AZURE_REGION=southeastasia
   ```

   也相容原本的 `AZURE_URL=https://southeastasia.api.cognitive.microsoft.com/`，未填 region 時會由網址判斷。

2. 執行：

   ```bash
   flutter pub get
   python3 scripts/build_android.py
   ```

   若 Flutter 不在 PATH：

   ```bash
   python3 scripts/build_android.py --flutter /path/to/flutter/bin/flutter
   ```

3. 取得 `build/app/outputs/flutter-apk/app-debug.apk`。換 Key 或 region 後，重新執行建置腳本並安裝新版 APK。

其他選項：`--verify-speech` 先以實際 Azure Key 驗證一次合成與評分；`--split-per-abi` 建置個別 CPU 架構 APK；`--mode release` 建置 release 模式。目前 release 使用開發簽章，上架前需在 `android/app/build.gradle.kts` 設定正式簽章。

### Key 如何放入 App

- 建置腳本只在本機讀取 `.env`，以隨機遮罩做 XOR，再轉 base64。
- Flutter 只取得編碼資料、遮罩與 region；暫存設定檔會在建置結束後刪除。
- APK 不包含 `.env` 或原始明文 Key；App 呼叫 Azure 時於記憶體中還原 Key。
- `.env`、建置檔案及暫存設定不提交 Git；Key 不會出現在建置命令或日誌中。
- **XOR/base64 是可逆混淆，不是防逆向保護。APK 內包含還原資料，因此持有 APK 的人可能取出 Key。**這是依目前需求採用的免輸入、無自建後端架構。

## Supabase（可選）

Supabase 僅用於帳號及跨裝置學習進度同步。未設定時完全使用手機本機進度，Azure 朗讀與評分不需要登入。

設定方式見 [supabase/README.md](supabase/README.md)。目前沒有 Supabase 專案設定，因此未啟用雲端同步，也未驗證線上登入／同步。

## 驗證

本次介面修改已通過靜態分析與 56 項 Flutter 自動測試（Azure 線上實測 1 項略過）；未重新建置 APK。

```bash
flutter analyze
flutter test
python3 -m unittest discover -s scripts -p 'test_*.py'
```

測試涵蓋教材一致性、男性用語、泰文間隔、隨機抽題與排序、切卡不重複計分、例句朗讀入口、學習紀錄、測驗、320px 手機版面、剪貼簿、直接 Azure 請求格式、錯誤處理、TTS 跨重啟／離線快取、建置編碼與暫存檔清理。

本環境沒有連接 Android 實機；麥克風、音訊路由仍需在手機驗收。

## 資料與圖示

- `thai_practice_dataset_400.json` 與 `assets/data/` 的副本保持相同。
- `thai`／`example_thai` 供分詞閱讀；`thai_native`／`example_thai_native` 保留原始泰文供語音使用。
- `node scripts/space-thai.mjs` 可重建閱讀空白，使用 ICU 泰語斷詞與複合詞補充清單。
- 字典保留女性語尾的詞義，讓學習者能辨識；100 個情境練習句採男性用語。
- [App icon](assets/brand/app-icon.png) 由 built-in Imagegen 產生；[完整 prompt](assets/brand/README.md) 已保留，圖示僅輸出 Android 尺寸。
- Noto Sans TC／[Noto Serif Thai](https://github.com/google/fonts/tree/main/ofl/notoserifthai) 字型隨 App 打包，授權在 `assets/fonts/`。

### 實作參考

- [Azure 短音訊 REST 與發音評估](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short)
- [Azure TTS REST](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech)
- [Peace Corps 泰語課程](https://files.peacecorps.gov/multimedia/audio/languagelessons/thailand/TH_Thai_Language_Lessons.pdf)

### 先前建置結果（本次未重新建置）

- Android 1.1.0（versionCode 2）測試 APK 已產生。
- 靜態分析通過；46 項 Flutter 自動測試與 4 項建置腳本測試通過。
- 已另外使用同一份內建編碼設定實測 Azure 男聲 TTS 與發音評分，完整流程通過。
- 已檢查解壓後的 APK 內容，沒有 `.env` 或原始明文 Key；仍包含可逆還原的編碼資料。
