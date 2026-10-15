# Changelog

所有重要變更都會記錄在此檔案

格式參考 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
版本規則遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Added

- 初始版本
- `:PenAdd <index> [note]` 將目前位置寫入對應 `.pen` 檔
- `:PenOpen <index>` 開啟書籤 buffer
- `:PenOpen`（省略 index）與 `require("pen.ui").open(nil, config)` 將所有 db_path 的書籤整合成單一 buffer，方便跨組搜尋與跳轉（顯示來源 `.pen` 檔名）
- `:PenLs` 顯示 `db_path` 列表，可直接跳轉編輯對應設定檔
- 使用 TSV 格式儲存書籤（`note\tfile:line:col`）
- 書籤 buffer 支援：
  - `/` 開啟即時篩選（輸入時立即匹配；預設只搜 note）
  - 篩選支援範圍前綴：`f:`／`p:` 只搜路徑、`a:`／`*:` 搜全部欄位（狀態列會顯示目前範圍）
  - `<CR>` 跳轉
  - `p` 切換浮動預覽
  - `q` 關閉、`<Esc>` 清除篩選
  - `<C-e>` 直接開啟該書籤所屬的 `.pen` 檔進行編輯（方便調整書籤內容）
- 自動建立 `db_path` 所需目錄
- `*.pen` 檔案的 filetype 偵測
- `:PenOpen` 時 buffer 名稱使用對應 `.pen` 檔名，不再顯示 `[No Name]`
- `display.columns` 支援 `index`／`db_index` 欄位：合併檢視（`:PenOpen` 無 index）時顯示該書籤所屬的 `db_path` 索引；單檔開啟時該欄自動隱藏
- `display.columns` 支援 `hl` 選項：可傳入 `vim.api.keyset.highlight` 的 table（或既有 group 名稱字串），為該欄位套用高亮顏色與樣式

### Changed

- `pen.bookmark.add` 的 `note` 參數支援傳入 `function`，會被呼叫以取得註解內容（方便 keymap 互動輸入）
- `pen.ui.open` 改為在目前 window 開啟，不再執行 `split`；`q` 改為刪除 scratch buffer 並回到前一個 buffer
- `/` 篩選改為即時過濾（輸入時立即更新列表，不需等到按下 Enter）
- 跳轉書籤時會將行號與欄位限制在有效範圍內，避免 `Invalid cursor line: out of range` 錯誤
- 在 oil.nvim buffer 加入書籤時，改為記錄游標下的真實檔案／目錄路徑（而非 `oil://` buffer 本身）
- 支援跳轉到 `oil://` 等特殊路徑（不再被 filereadable 檢查擋住）
- `display.columns` 如果其計算結果為 `nil` 那麼此欄位將不顯示（用於 `field = "source"`、`field = "index"`，以及 `format` 回傳 `nil`）
- `/` 篩選按下 `<CR>` 確認後會自動離開 insert 模式，無需再按一次 `<Esc>`
- 預覽視窗（`p`）開啟後會隨著游標移動即時更新內容

### Fixed

- 修復書籤行號超出檔案範圍時跳轉失敗的問題

