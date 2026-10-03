# 韓語與越南語教材說明

韓語與越南語教材為本專案自編的生活用語，每種語言各有 500 個詞彙、200 個片語及 100 個情境句子，附繁體中文。涵蓋問候、家庭、飲食、數字、時間、購物、交通、旅行、住宿、健康、居家、工作、學習與休閒。沒有引用或翻譯第三方教材的完整字表。

「入門／基礎」是專案內部的練習分組，並非 TOPIK 或其他檢定的官方字表。初版尚未經母語教師逐條審訂；詞彙與情境句可依回饋更新，須保留既有 ID 對應的學習內容。

- 韓語顯示韓文字母，不另加羅馬拼音。詞彙中的動詞以字典形呈現，生活句主要使用禮貌體。數字單字以漢字數詞為主；「한 시간」等片語則示範固有數詞的實際用法。
- 越南語顯示保留聲調的國語字，不重複顯示另一行相同文字。詞彙使用常見越南語，可能有地區別的同義說法。句子中的 `tôi`、`bạn` 是一般教學情境；實際稱呼需配合年齡、身分與關係調整。
- 男／女設定切換朗讀聲音，不自動改寫韓語敬語或越南語人稱。新教材不提供泰語式的男女文句變體。
- 日語仍使用漢字／假名規則，泰語仍使用原有拼音與已審查的男女文句。

根目錄 JSON 是可編輯來源，`assets/data/` 是離線副本；`scripts/update_dataset.py` 一次同步四種語言的副本及 SHA-256。新語言的遠端更新檔須提交到 GitHub `main` 後才可下載；未發布或離線時使用內建教材。

語音語系與聲音使用 [Microsoft Azure 語音支援表](https://learn.microsoft.com/zh-tw/azure/ai-services/speech-service/language-support)：韓語 `ko-KR`（InJoon／SunHi）、越南語 `vi-VN`（NamMinh／HoaiMy）。兩種語系均列於 [Microsoft 發音評估支援清單](https://github.com/MicrosoftDocs/azure-ai-docs/blob/main/articles/ai-services/speech-service/includes/language-support/pronunciation-assessment.md)。程式測試以模擬請求檢查語系、聲音、參考文字與快取；未執行新語言的 Azure 線上或 Android 實機驗證。

韓文字型來自 Google Fonts 的 [Noto Sans KR](https://github.com/google/fonts/tree/main/ofl/notosanskr)，依 SIL Open Font License 1.1 使用，原授權保留於 `assets/fonts/OFL-NotoSansKR.txt`。`NotoSansKR.ttf` 保留完整來源供重新裁切，APK 只打包涵蓋目前韓文的 `NotoSansKR.subset.ttf`。越南文使用既有 Noto Sans TC，其裁切範圍已納入全部教材的聲調字元。更新教材後執行 `scripts/subset_fonts.py` 重新裁切並檢查。
