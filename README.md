# A4 Notice Poster Skill

一個用於 Codex 的 A4 公告海報製作技能。它先釐清需求與參考圖用途，再生成含文字的完整視覺概念；使用者確認後，重建成無字背景與本機字型文字圖層，最後輸出可印刷成品。

## 主要能力

- 支援只有主題、已有文案、舊版重排與參考圖等入口。
- 參考圖會先確認「沿用風格、保留指定特徵、重新設計」。
- 內建六種海報視覺方向。
- 三個確認點：需求與文案、完整視覺概念、正式排版畫布。
- HTML 排版畫布可預覽本機字型、文字位置、字級與對齊。
- PowerShell renderer 支援同張海報使用多種本機字型。
- 預設輸出 A4 直式 `2480 × 3508`、`300 DPI` PNG。

## 預裝風格

- `clinical-trust`：醫療信賴
- `public-institutional`：公部門正式
- `warm-community`：溫暖社區
- `high-alert`：高辨識警示
- `editorial-minimal`：編輯極簡
- `human-centered-illustration`：人物情境插畫

詳細規則位於 `references/preset-styles.md`。

## 安裝

將 repository clone 到 Codex skills 目錄：

```powershell
git clone https://github.com/ayase0307/a4-notice-poster-skill.git "$env:USERPROFILE\.codex\skills\a4-notice-poster"
```

重新開啟 Codex 後，可直接描述 A4 公告海報需求，或明確指定 `$a4-notice-poster`。

## 執行需求

- Windows PowerShell
- `System.Drawing`
- 已安裝的中文字型
- 可用的圖片生成功能

## 驗證

```powershell
./scripts/render_a4_poster.ps1 -ConfigPath ./poster-config.json
./scripts/verify_poster.ps1 -ImagePath ./poster.png -ConfigPath ./poster-config.json
```

`verify_poster.ps1` 會檢查尺寸、DPI、設定中宣告的字型與 SHA256。文案正確性與視覺品質仍需依 `SKILL.md` 檢查實際輸出。

## License

MIT
