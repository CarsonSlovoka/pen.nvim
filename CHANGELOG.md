# Changelog

所有重要變更都會記錄在此檔案

格式參考 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
版本規則遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Added

- 初始版本
- `:PenAdd <index> [note]` 將目前位置寫入對應 `.pen` 檔
- `:PenOpen <index>` 開啟書籤 buffer
- `:PenLs` 顯示 `db_path` 列表，可直接跳轉編輯對應設定檔
- 使用 TSV 格式儲存書籤（`note\tfile:line:col`）
- 書籤 buffer 支援：
  - `/` 開啟即時篩選（輸入時立即匹配）
  - `<CR>` 跳轉
  - `p` 切換浮動預覽
  - `q` 關閉、`<Esc>` 清除篩選
- 自動建立 `db_path` 所需目錄
- `*.pen` 檔案的 filetype 偵測
- `:PenOpen` 時 buffer 名稱使用對應 `.pen` 檔名，不再顯示 `[No Name]`

### Changed

- `pen.bookmark.add` 的 `note` 參數支援傳入 `function`，會被呼叫以取得註解內容（方便 keymap 互動輸入）
- `pen.ui.open` 改為在目前 window 開啟，不再執行 `split`；`q` 改為刪除 scratch buffer 並回到前一個 buffer
- `/` 篩選改為即時過濾（輸入時立即更新列表，不需等到按下 Enter）
- 跳轉書籤時會將行號與欄位限制在有效範圍內，避免 `Invalid cursor line: out of range` 錯誤
- 在 oil.nvim buffer 加入書籤時，改為記錄游標下的真實檔案／目錄路徑（而非 `oil://` buffer 本身）
- 支援跳轉到 `oil://` 等特殊路徑（不再被 filereadable 檢查擋住）

### Fixed

- 修復書籤行號超出檔案範圍時跳轉失敗的問題

