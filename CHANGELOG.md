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
  - `/` 篩選只保留包含關鍵字的項目
  - `<CR>` 跳轉
  - `p` 切換浮動預覽
  - `q` 關閉、`<Esc>` 清除篩選
- 自動建立 `db_path` 所需目錄
- `*.pen` 檔案的 filetype 偵測
- `:PenOpen` 時 buffer 名稱使用對應 `.pen` 檔名，不再顯示 `[No Name]`

[Unreleased]: https://github.com/CarsonSlovoka/pen.nvim/compare/v0.0.0...HEAD
