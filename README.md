# pen.nvim

輕量級 Neovim 書籤管理插件，將多組書籤分別儲存在 `.pen` 檔案中

## 功能

- 將目前游標位置與註解寫入指定的 `.pen` 檔案（在 oil.nvim 中會記錄游標下的真實路徑）
- 提供 `:PenAdd`、`:PenOpen` 與 `:PenLs` 指令
- 在書籤 buffer 中：
  - `/` 開啟即時篩選（輸入時立即匹配，不必等到按下 Enter；按下 `<CR>` 後自動回到 normal 模式）
  - `<CR>` 跳轉到該位置
  - `p` 切換浮動預覽視窗（顯示前後各 N 行上下文，N 可由 config 或即時調整；開啟後會隨著游標移動即時更新）
  - `}` 增加預覽上下文行數
  - `{` 減少預覽上下文行數
  - `q` 關閉 buffer
  - `<Esc>` 關閉預覽（若開啟）並清除篩選

## 安裝

支援 Neovim 0.12 以上，使用 `packadd` 或手動放入 packpath 即可，不依賴任何第三方插件管理器

```lua
vim.cmd.packadd("pen.nvim")
require("pen").setup({
  db_path = {
    vim.fn.stdpath("data") .. "/pen.nvim/bookmark_01.tsv",
    vim.fn.stdpath("data") .. "/pen.nvim/bookmark_02.tsv",
    -- ...
    vim.fn.stdpath("data") .. "/pen.nvim/bookmark_09.tsv",
  },
  -- 可選：自訂書籤列表的顯示欄位與對齊
  display = {
    columns = {
      { field = "index",  width = 4,  align = "right",  hl = "Comment" },  -- 僅在 :PenOpen（無 index）時有值
      { field = "source", width = 16, hl = "Comment" },                    -- 僅在 :PenOpen（無 index）時有值
      { field = "note", width = 40},
      { field = "file", width = 15, path = ":t", hl = { fg = "#88ccff", italic = true } },
      { field = "file", width = 50, path = "relative" }, -- absolute, basename
      { field = "line", width = 6, align = "right", hl = { fg = "#aaaaaa" } },
      { field = "col", width = 4, align = "right" },
    },
    separator = "  ",
  },
  -- 可選：預覽行為
  preview = {
    context = 5,      -- 前後各顯示幾行（可用 { } 即時調整）
    auto_open = true, -- 進入列表時自動開啟預覽
    syntax = true,    -- 依據檔案副檔名啟用語法高亮（預設開啟；找不到對應規則時不影響）
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
| `p`     | 切換浮動預覽（開啟後會隨游標即時更新預覽內容） |
| `}`     | 增加預覽上下文大小（前後各多顯示一行） |
| `{`     | 減少預覽上下文大小（前後各少顯示一行） |
| `/`     | 開啟即時篩選（預設只搜 note；輸入時立即更新列表；`<CR>` 確認後自動離開 insert 模式） |
| `<Esc>` | 關閉預覽（若開啟）並清除篩選（在篩選視窗中也會清除並關閉） |
| `q`     | 關閉 buffer（回到前一個 buffer） |
| `<C-e>` | 開啟並編輯此書籤所屬的 `.pen` 檔（方便手動調整） |

篩選範圍前綴（在 `/` 輸入框中）：

| 輸入 | 搜尋範圍 |
|------|----------|
| `關鍵字` | 只搜 **note**（預設） |
| `f:關鍵字` 或 `p:關鍵字` | 只搜檔案路徑 |
| `a:關鍵字` 或 `*:關鍵字` | 搜尋所有顯示欄位 |

狀態列會顯示目前範圍，例如 `Pen [note: foo] (3/20)` 或 `Pen [path: src] (2/20)`。

在 PenLs buffer 中：

| 按鍵    | 動作                     |
|---------|--------------------------|
| `<CR>`  | 開啟並編輯對應 `.pen` 檔 |
| `q`     | 關閉 buffer              |
| `<Esc>` | 關閉 buffer              |

## 設定

- `db_path`：必須為絕對路徑的 table，插件會自動建立父目錄
- `display`：控制 `:PenOpen` 時書籤列表的顯示方式（可自訂欄位順序、寬度與格式）
- `preview`：控制預覽視窗的行為

### preview 設定

| 鍵 | 預設 | 說明 |
|----|------|------|
| `context` | `5` | 預覽時顯示書籤目標行前後各幾行 |
| `auto_open` | `true` | 進入書籤列表（`:PenOpen`）時是否自動開啟預覽視窗 |

在書籤列表中可即時調整上下文大小（類似 lazygit 的 diff context）：

- `}` 增加（前後各多一行）
- `{` 減少（前後各少一行）

調整後若預覽視窗已開啟，會立即更新內容並調整視窗高度；標題也會顯示目前的 `±N`。此調整僅對目前的書籤 buffer 有效，不會寫回 config。

### display 設定

`display.columns` 是一個 table，每個元素定義一個欄位：

| 鍵 | 說明 |
|----|------|
| `field` | 欄位名稱：`note`、`file`、`line`、`col`、`source`（合併檢視時的來源檔名）、`index`／`db_index`（合併檢視時的 db_path 索引）、`loc`（line:col）或其他 bookmark 欄位 |
| `width` | 欄寬（顯示寬度），超過會截斷並加上 `...`，不足則補空白以對齊 |
| `align` | `"left"`（預設）或 `"right"` |
| `path` | 僅對 `file` 有效：`"absolute"` / `"abs"` / `":p"`、`"relative"` / `"rel"` / `":."`、`"basename"` / `"base"` / `":t"`，或自訂 fnamemodify 修飾字串，或 function(file) |
| `format` | function(bm) ，若提供則優先使用此函式產生該欄內容。回傳 `nil` 時整欄隱藏（用於條件顯示） |
| `hl` | 高亮選項，內容為 `vim.api.keyset.highlight` 可接受的 table（如 `{ fg = "#ff8800", bold = true }`）。也可直接傳字串作為既有 highlight group 名稱。整欄（含補齊空白）會套用此高亮 |

`display.separator` 為欄位間的分隔字串，預設為兩個空白

範例（合併檢視顯示索引與來源，路徑用絕對路徑）：

```lua
display = {
  columns = {
    { field = "index", width = 4, align = "right" }, -- 僅在 :PenOpen（無 index）時有值
    { field = "source", width = 16 },               -- 僅在 :PenOpen（無 index）時有值
    { field = "note", width = 36 },
    { field = "file", width = 60, path = "absolute" },
    { field = "loc", width = 10, align = "right" },
  },
  separator = " │ ",
}
```

或使用自訂 format 函式（回傳 nil 可隱藏整欄）：

```lua
{
  width = 4,
  align = "right",
  format = function(bm)
    -- 僅合併檢視時顯示 index
    return bm.db_index and tostring(bm.db_index) or nil
  end,
}
```

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
