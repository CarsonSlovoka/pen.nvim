# pen.nvim

輕量級 Neovim 書籤管理插件，將多組書籤分別儲存在 `.pen` 檔案中

## 功能

- 將目前游標位置與註解寫入指定的 `.pen` 檔案
- 提供 `:PenAdd`、`:PenOpen` 與 `:PenLs` 指令
- 在書籤 buffer 中：
  - `/` 篩選只顯示包含關鍵字的項目
  - `<CR>` 跳轉到該位置
  - `p` 切換浮動預覽視窗（顯示前後各 5 行上下文）
  - `q` 關閉 buffer
  - `<Esc>` 清除篩選

## 安裝

支援 Neovim 0.12 以上，使用 `packadd` 或手動放入 packpath 即可，不依賴任何第三方插件管理器

```lua
vim.cmd.packadd("pen.nvim")
require("pen").setup({
  db_path = {
    vim.fn.stdpath("data") .. "/pen.nvim/bookmark_01.pen",
    vim.fn.stdpath("data") .. "/pen.nvim/bookmark_02.pen",
    -- ...
    vim.fn.stdpath("data") .. "/pen.nvim/bookmark_09.pen",
  },
})
```

**注意**：路徑必須包含分隔符 `/`，插件會自動建立所需目錄

## 使用方式

```vim
:PenAdd 1 note text here     " 寫入 bookmark_01.pen 並附上註解
:PenAdd 9                    " 寫入 bookmark_09.pen，註解預設為目前檔名
:PenOpen 1                   " 開啟第 1 組書籤 buffer（buffer 名稱為對應檔名）
:PenLs                       " 列出所有 db_path，<CR> 跳轉編輯該設定檔
```

在 pen buffer 中的按鍵：

| 按鍵    | 動作                     |
|---------|--------------------------|
| `<CR>`  | 跳轉到書籤位置           |
| `p`     | 切換浮動預覽             |
| `/`     | 篩選列表                 |
| `<Esc>` | 清除篩選                 |
| `q`     | 關閉 buffer              |

在 PenLs buffer 中：

| 按鍵    | 動作                     |
|---------|--------------------------|
| `<CR>`  | 開啟並編輯對應 `.pen` 檔 |
| `q`     | 關閉 buffer              |
| `<Esc>` | 關閉 buffer              |

## 設定

僅支援 `db_path`，必須為絕對路徑的 table，插件會自動建立父目錄

## 檔案格式

書籤以 TSV（tab 分隔）儲存，格式為：

```
重要功能	/absolute/path/to/file.lua:42:10
```

註解中若含有 tab 會被替換成空白，以避免破壞格式

## 版本

目前版本：**Unreleased**

## 授權

MIT
