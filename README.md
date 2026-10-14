# pen.nvim

輕量級 Neovim 書籤管理插件，將多組書籤分別儲存在 `.pen` 檔案中

## 功能

- 將目前游標位置與註解寫入指定的 `.pen` 檔案（在 oil.nvim 中會記錄游標下的真實路徑）
- 提供 `:PenAdd`、`:PenOpen` 與 `:PenLs` 指令
- 在書籤 buffer 中：
  - `/` 開啟即時篩選（輸入時立即匹配，不必等到按下 Enter）
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
:PenOpen 1                   " 在目前 window 開啟第 1 組書籤 buffer（不再 split）
:PenOpen                     " 省略索引：將所有 db_path 的書籤整合成一個 buffer，方便跨組搜尋
:PenLs                       " 列出所有 db_path，<CR> 跳轉編輯該設定檔
```

### 程式化呼叫（keymap 範例）

`require("pen.ui").open(idx, config)`：`idx` 為數字時開啟該組；傳 `nil` 時會將所有 `db_path` 的書籤整合成一個列表供篩選與跳轉。

`pen.bookmark.add` 的第二個參數 `note` 可以是 `string`、`nil`，或 **function**。  
若傳入 function，會被呼叫並使用其回傳值作為註解（適合互動式輸入）：

```lua
local pen_bookmark = require("pen.bookmark")
local config = require("pen").get_config()

vim.keymap.set("n", "<leader>ma1", function()
  pen_bookmark.add(1, function()
    return vim.fn.input("Note: ")
  end, config)
end, { desc = "Add bookmark to 1 (prompt note)" })
```

在 pen buffer 中的按鍵：

| 按鍵    | 動作                     |
|---------|--------------------------|
| `<CR>`  | 跳轉到書籤位置           |
| `p`     | 切換浮動預覽             |
| `/`     | 開啟即時篩選（輸入時立即更新列表） |
| `<Esc>` | 清除篩選                 |
| `q`     | 關閉 buffer（回到前一個 buffer） |

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
