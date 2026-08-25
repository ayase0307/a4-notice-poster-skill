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

## 同一主題的風格比較

以下六張都使用同一主題「社區免費健康檢查日」與相同活動資訊。圖片先生成無字背景，再用本機字型疊入可驗證的繁體中文；因此可以直接比較各預設的構圖、配色、插畫語言與資訊層級。

<table>
  <tr>
    <td align="center"><strong>clinical-trust｜醫療信賴</strong><br><a href="assets/style-previews/clinical-trust.jpg"><img src="assets/style-previews/clinical-trust.jpg" width="420" alt="醫療信賴風格的社區免費健康檢查日海報"></a></td>
    <td align="center"><strong>public-institutional｜公部門正式</strong><br><a href="assets/style-previews/public-institutional.jpg"><img src="assets/style-previews/public-institutional.jpg" width="420" alt="公部門正式風格的社區免費健康檢查日海報"></a></td>
  </tr>
  <tr>
    <td align="center"><strong>warm-community｜溫暖社區</strong><br><a href="assets/style-previews/warm-community.jpg"><img src="assets/style-previews/warm-community.jpg" width="420" alt="溫暖社區風格的社區免費健康檢查日海報"></a></td>
    <td align="center"><strong>high-alert｜高辨識警示</strong><br><a href="assets/style-previews/high-alert.jpg"><img src="assets/style-previews/high-alert.jpg" width="420" alt="高辨識警示風格的社區免費健康檢查日海報"></a></td>
  </tr>
  <tr>
    <td align="center"><strong>editorial-minimal｜編輯極簡</strong><br><a href="assets/style-previews/editorial-minimal.jpg"><img src="assets/style-previews/editorial-minimal.jpg" width="420" alt="編輯極簡風格的社區免費健康檢查日海報"></a></td>
    <td align="center"><strong>human-centered-illustration｜人物情境插畫</strong><br><a href="assets/style-previews/human-centered-illustration.jpg"><img src="assets/style-previews/human-centered-illustration.jpg" width="420" alt="人物情境插畫風格的社區免費健康檢查日海報"></a></td>
  </tr>
</table>

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
