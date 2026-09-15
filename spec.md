App Name: ThaiTalk

**Flutter + Azure Speech**

原因是 Flutter 可以先同時做 iOS / Android；Supabase 處理帳號、資料庫、學習進度很方便；而 Azure Speech 現在有支援泰文 `th-TH` 的發音評估，可以直接取得發音準確度、流暢度、完整度等評分，比自己從錄音演算法開始做簡單非常多。([Microsoft Learn][1]) Azure 目前也有多個泰文 TTS 語音，例如 `th-TH-PremwadeeNeural`、`th-TH-NiwatNeural` 等，可以拿來念單字和句子。([Microsoft Learn][2])

「單字/句字資料」 thai_practice_dataset_400.md

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


## 最新確認需求（2026-09-15）

- 僅支援 Android，不需要 iOS、桌面或網頁版。
- App 直接透過 HTTPS 呼叫 Azure Speech，不使用自建語音後端。
- 建置時從本機 `.env` 讀取 Azure Speech Key，以可逆 XOR/base64 編碼內建 APK；使用者不需輸入 Key。原始 `.env` 不打包、不提交 Git。此編碼不保證防逆向擷取。
- 泰文情境句採男性用語，預設 Niwat 男聲。
- 泰文詞語间加空白供初學者閱讀；保留原始泰文作為語音輸入。
- 單字與句子提供複製到剪貼簿按鈕。
- TTS 保存本機持久快取，相同文字、聲音及語速重用已下載音檔。
- Supabase 帳號／進度同步為選用；本機學習與 Azure 語音無須登入。
- 單字／句子頁只顯示篩選與練習入口，不列出個別內容卡片。
- 每次開始單字卡或測驗時，從目前篩選範圍隨機抽選 10 個並打亂順序；不足 10 個時使用全部，單輪不重複。左右切換維持該輪順序。
- 單字卡／測驗卡使用單一手機畫面的矩形卡面。單字卡直接顯示中文；測驗以中文選項作答。
- 朗讀、慢速朗讀、發音練習用圖示，置於文字下方同一卡框；卡面左右箭頭切換上／下一張。
- 單字例句從卡片圖示查看，可朗讀與複製，沿用男聲／快取；例句不提供錄音練習。
- 泰文字型使用隨 App 打包的 Noto Serif Thai。
- **只有使用者明確要求 build 時才建置 APK；平常修改只進行靜態分析與測試。**
