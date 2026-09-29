# ThaiTalk

Android 泰語／日語學習 App，以 Flutter 製作。繁體中文介面，每種語言各有 500 個單字、200 個片語、100 個句子。可切換語言與男女聲，並用獨立按鈕播放 Local／Azure TTS；錄音發音評分使用 Azure。

## 安裝與使用

安裝對應手機 CPU 的 `build/app/outputs/flutter-apk/*-release.apk` 後即可使用；**不需要自建後端，也不需要使用者輸入 API Key**。

目前已建置包含 500 個單字、200 個片語、100 個句子的 Release APK；產物與 CPU 對照見下方建置章節。

- 單字、片語、句子均有泰文、拼音與中文；原有 300 個單字另有例句。
- 設定首項可切換 🇹🇭 ภาษาไทย／🇯🇵 日本語。日語教材以 N3–N2 程度的生活詞彙、短語及句子為主，顯示漢字、假名讀音及中文；純片假名不重複顯示假名，也不顯示羅馬拼音。
- 泰語與日語的本機收藏、複習、分數和每日進度分開保存。日語模式目前只儲存在本機；泰語帳號同步維持原有功能。
- 主題／程度篩選、搜尋、間隔複習、單字卡及四選一測驗。
- 單字／片語／句子頁顯示篩選與練習入口。可在設定選擇每輪 10／20／30／50 題；開始時隨機抽選，不足時使用全部，單輪不重複。
- 結果頁的「再練習一次」會從目前篩選範圍重新抽選，優先選沒有出現在上一輪的內容；題庫不足時才重複。
- 手機單一卡面直接顯示單字中文；左右箭頭切卡，朗讀／發音練習使用同框圖示。測驗以中文選項作答。
- 有例句的單字卡提供例句按鈕；單字、片語及句子卡均可使用 Local TTS、Azure TTS 與錄音練習。例句顯示泰文、拼音與中文，可朗讀及複製。
- 一鍵複製單字、片語或句子到剪貼簿。
- 首頁右上角齒輪開啟設定頁：說話者「男／女」及每輪 10／20／30／50 題，選擇後自動保存，預設男聲與 10 題。TTS 直接由卡片上的 Local／Azure 播放按鈕選擇。
- 例句及情境句依說話者切換自稱、禮貌用語與對應拼音；顯示、複製、朗讀及評分使用相同版本。字典單字保留原本詞義。
- Local／Azure 播放按鈕使用正常速度，已移除慢速按鈕，涵蓋單字、句子及例句；錄音準確度／流暢度／完整度由 Azure 評分。
- Local 只選擇已安裝的離線泰語語音，不需 Azure Key 或網路，也不讀寫音檔快取。
- Azure 男聲使用 Niwat、女聲使用 Premwadee；依原始泰文、聲音與速度保存音檔快取（上限 64 MB）。相同內容優先播放快取，重新開啟 App 後仍可使用；男女聲及不同速度各自保存。
- 學習進度、每日目標、連續學習天數和 XP 自動保存在手機。

使用 Local TTS 前請在 Android 系統「文字轉語音」設定安裝離線泰語語音資料；未安裝時 App 會顯示提示。本機聲音由手機語音引擎提供；有性別資料時優先選擇對應聲音，否則使用可用的離線泰語聲音。

每次發音評分需要網路，App 透過 HTTPS 直接呼叫 Azure。錄音最長 30 秒，只在送出評分時傳送，不會保存在學習紀錄或資料庫中。沒有 Azure Key 的一般開發建置仍可使用本機朗讀及學習。

## 教材啟動更新

App 每次啟動先讀取手機保存的教材（初次安裝使用 APK 內建教材），再檢查 GitHub `main` 分支：

- 教材：[thai_practice_dataset.json](https://raw.githubusercontent.com/sibuzu/thaitalk/main/thai_practice_dataset.json)
- SHA-256：[thai_practice_dataset.json.sha256](https://raw.githubusercontent.com/sibuzu/thaitalk/main/thai_practice_dataset.json.sha256)
- 日語教材：[japanese_practice_dataset.json](https://raw.githubusercontent.com/sibuzu/thaitalk/main/japanese_practice_dataset.json)
- 日語 SHA-256：[japanese_practice_dataset.json.sha256](https://raw.githubusercontent.com/sibuzu/thaitalk/main/japanese_practice_dataset.json.sha256)

只有 SHA-256 不同才下載 JSON；版本以檔案內容的 checksum 判定。校驗檔請求最多等待 3 秒，教材下載最多等待 5 秒、大小上限 5 MiB。下載後先驗證 SHA-256、JSON 欄位、唯一 ID、男女版本及顯示／語音文字一致性，再以暫存檔寫入與原子重新命名替換 Android 私有儲存中的教材。APK 內建資料本身不會被改寫。

斷網、404、逾時、下載損壞或寫入失敗，均保留舊教材；本機檔案損壞時回退至 APK 內建資料。首頁、單字／片語／句子及測驗選項使用同一份已接受的版本。更新不清除收藏與學習紀錄，因此既有教材 ID 不應重新編號或改給另一個單字。

發布教材更新：

```bash
# 編輯根目錄教材後，同步 APK 副本並重新產生 SHA-256
python3 scripts/update_dataset.py
python3 scripts/update_dataset.py --check
```

一起提交根目錄 JSON、`assets/data/` 副本及 `.sha256` 檔，再 push 到 `main`。`apply_gender_variants.py` 與 `space-thai.mjs` 產生教材時也會更新 checksum。新版 App 不需要重新安裝即可取得之後的教材更新；**目前已安裝的舊 APK，仍需先安裝含此更新功能的新 APK 一次**。

日語單字資料來源與修改聲明見 [Japanese curriculum attribution](docs/attribution/japanese-curriculum.md)；日語例句與短語為此專案編寫。N3／N2 是社群估計程度，並非 JLPT 官方字表。

## 建置 Android APK（預設瘦身版）

需要 Flutter 3.44+ / Dart 3.12+、Python 3、JDK 17 與 Android SDK。Android 最低 API 24。只有使用者明確要求 build 時才執行建置。

專案根目錄 `.env` 保留現有的 `AZURE_APIKEY`、`AZURE_REGION`（或 `AZURE_URL`）。執行：

```bash
cd /home/jack/git/thaitalk
python3 scripts/build_android.py \
  --flutter /home/jack/snap/flutter/common/flutter/bin/flutter
```

預設使用 **Release 編譯＋依 CPU 分開打包**。未建立 `android/key.properties` 時，自動用現有 debug key 簽署，可直接安裝；若有該檔則使用指定的正式金鑰。編譯模式與簽章金鑰各自獨立，使用 debug key 不會把 release 變成 debug 編譯。

產物位於 `build/app/outputs/flutter-apk/`，每個檔案均可獨立安裝：

| APK | CPU |
|---|---|
| `app-arm64-v8a-release.apk` | ARM64 |
| `app-armeabi-v7a-release.apk` | ARM32 |
| `app-x86_64-release.apk` | x86-64 |

只建置 ARM64 可加 `--target-platform android-arm64`；`--universal` 產生包含所有選定架構的較大單一 `app-release.apk`。需要 debug 時加 `--mode debug`，搭配 `--universal` 可取得原本的 `app-debug.apk`。

`--verify-speech` 會先用 Azure 評估錄音，需設定 `AZURE_TEST_WAV`（16 kHz 單聲道 PCM WAV）與 `AZURE_TEST_REFERENCE`；不呼叫 Azure TTS。

### 體積調整

- 預設 Release，使用 Flutter 既有的 R8 程式與資源縮減。
- 依 CPU 分開 APK，避免一支手機下載其他架構的引擎。
- Noto Sans TC 從 11,941,968 bytes 裁切成 581,688 bytes，保留目前介面、教材、拉丁字母與標點需要的字形及字重。Noto Serif Thai 完整保留。
- 原始中文字型保留於 `assets/fonts/NotoSansTC.ttf`，APK 只打包 `NotoSansTC.subset.ttf`；完整字型不會隨 App 打包。其他動態中文字由 Android 系統字型補足。
- 品牌素材只打包使用中的 PNG，不包含產圖說明與工具腳本。

新增介面或教材文字後可重新產生並檢查字型：

```bash
python3 -m venv /tmp/thaitalk-font-tools
/tmp/thaitalk-font-tools/bin/pip install fonttools==4.65.0
/tmp/thaitalk-font-tools/bin/python scripts/subset_fonts.py
/tmp/thaitalk-font-tools/bin/python scripts/subset_fonts.py --check
```

本次已建置三種 CPU 的 Release APK，並確認各 APK 內含 500 個單字、200 個片語、100 個句子；尚未在實機安裝驗證。

### 正式簽章（選用，自行安裝不需要）

已有正式 keystore 請沿用。首次建立：

```bash
mkdir -p "$HOME/.keystores"
keytool -genkeypair -v -storetype JKS -keyalg RSA -keysize 2048 \
  -validity 10000 -alias thaitalk \
  -keystore "$HOME/.keystores/thaitalk-release.jks"
```

建立 `android/key.properties`，填入實際路徑與密碼：

```properties
storeFile=/home/jack/.keystores/thaitalk-release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=thaitalk
keyPassword=YOUR_KEY_PASSWORD
```

此檔案是 Java properties 格式；密碼若含反斜線，需寫成 `\\`。金鑰建立時若沿用 keystore 密碼，兩個密碼欄填相同值。執行 `chmod 600 android/key.properties`，再用上方建置命令即可。請備份 keystore 與密碼，後續更新沿用同一把金鑰；keystore 與設定檔均已排除 Git。

### Key 如何放入 App

- 建置腳本只在本機讀取 `.env`，以隨機遮罩做 XOR，再轉 base64。
- Flutter 只取得編碼資料、遮罩與 region；暫存設定檔會在建置結束後刪除。
- APK 不包含 `.env` 或原始明文 Key；App 呼叫 Azure 時於記憶體中還原 Key。
- `.env`、建置檔案及暫存設定不提交 Git；Key 不會出現在建置命令或日誌中。
- **XOR/base64 是可逆混淆，不是防逆向保護。APK 內包含還原資料，因此持有 APK 的人可能取出 Key。**這是依目前需求採用的免輸入、無自建後端架構。

## Supabase（可選）

Supabase 僅用於帳號及跨裝置學習進度同步。未設定時完全使用手機本機進度，朗讀與 Azure 評分不需要登入。

設定方式見 [supabase/README.md](supabase/README.md)。目前沒有 Supabase 專案設定，因此未啟用雲端同步，也未驗證線上登入／同步。

## 驗證

設定頁及獨立 TTS 按鈕修改已通過靜態分析、110 項 Flutter 測試與 8 項 Python 單元測試；Azure 線上實測 1 項略過。建置腳本測試使用模擬建置，不產生 APK。未重新建置 APK，尚未在 Android 實機驗證本機語音引擎。

```bash
flutter analyze
flutter test
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/apply_gender_variants.py --check
python3 scripts/update_dataset.py --check
```

測試涵蓋設定保存與寫入失敗復原、男女用語、教材一致性、泰文間隔、隨機抽題與排序、切卡不重複計分、例句朗讀入口、學習紀錄、測驗、320px 手機版面、剪貼簿、直接 Azure 請求格式、錯誤處理、本機 TTS 離線語音篩選、不使用快取、Azure 音檔快取與男女聲隔離、缺少語音提示、切換來源及取消朗讀、建置編碼與暫存檔清理。

本環境沒有連接 Android 實機；麥克風、音訊路由仍需在手機驗收。

## 資料與圖示

- `thai_practice_dataset.json` 與 `assets/data/` 的副本保持相同。
- `thai`／`example_thai` 供分詞閱讀；`thai_native`／`example_thai_native` 保留原始泰文供語音使用。
- `node scripts/space-thai.mjs` 可重建閱讀空白，使用 ICU 泰語斷詞與複合詞補充清單。
- 男性版為教材基準，`female` 欄位保存經檢查的女性版；100 個情境句及 68 個需調整的單字例句可切換。中性例句與字典中的性別詞義保留不變。
- `scripts/gender_variants.json` 保存男女對照，`python3 scripts/apply_gender_variants.py` 可同步兩份教材，`--check` 可檢查一致性；例句拼音依教材與 `scripts/example_romanization.py` 的明確詞彙對照產生，未知詞會停止產生以待補充。
- [App icon](assets/brand/app-icon.png) 由 built-in Imagegen 產生；[完整 prompt](assets/brand/README.md) 已保留，圖示僅輸出 Android 尺寸。
- Noto Sans TC／[Noto Serif Thai](https://github.com/google/fonts/tree/main/ofl/notoserifthai) 字型隨 App 打包，授權在 `assets/fonts/`。

### 實作參考

- [Azure 短音訊 REST 與發音評估](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short)
- [flutter_tts：Android 系統文字轉語音](https://pub.dev/packages/flutter_tts)
- [Peace Corps 泰語課程](https://files.peacecorps.gov/multimedia/audio/languagelessons/thailand/TH_Thai_Language_Lessons.pdf)

### 先前建置結果（本次未重新建置）

- Android 1.1.0（versionCode 2）測試 APK 已產生。
- 靜態分析通過；46 項 Flutter 自動測試與 4 項建置腳本測試通過。
- 已另外使用同一份內建編碼設定實測 Azure 男聲 TTS 與發音評分，完整流程通過。
- 已檢查解壓後的 APK 內容，沒有 `.env` 或原始明文 Key；仍包含可逆還原的編碼資料。
