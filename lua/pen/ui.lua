--- pen.nvim UI module
--- Handles the bookmark list buffer, filtering, preview, and jumping.
local M = {}

-- Store state per buffer
local buffer_state = {}

-- Namespace for column highlights
local hl_ns = vim.api.nvim_create_namespace("pen_display")

-- Cache of highlight group names created from hl option tables
local hl_group_cache = {}

--- Get or create a highlight group for the given vim.api.keyset.highlight options.
--- @param hl table|string|nil
--- @return string|nil group name, or nil if no highlight
local function get_hl_group(hl)
  if not hl then
    return nil
  end
  if type(hl) == "string" then
    -- Allow existing group name as a convenience
    return hl
  end
  if type(hl) ~= "table" then
    return nil
  end
  local key = vim.inspect(hl)
  local cached = hl_group_cache[key]
  if cached then
    return cached
  end
  local name = "PenHl_" .. vim.fn.sha256(key):sub(1, 12)
  -- Define the group globally so it can be used by nvim_buf_add_highlight
  vim.api.nvim_set_hl(0, name, hl)
  hl_group_cache[key] = name
  return name
end

--- Truncate a string to a given display width, appending "..." if needed.
--- @param str string|any
--- @param max_width number|nil
--- @return string
local function truncate_to_display_width(str, max_width)
  if not max_width or max_width <= 0 then
    return str
  end
  str = tostring(str or "")
  if vim.fn.strdisplaywidth(str) <= max_width then
    return str
  end
  local ellipsis = "..."
  local ellipsis_w = 3
  if max_width <= ellipsis_w then
    return ellipsis:sub(1, max_width)
  end
  local target = max_width - ellipsis_w
  local char_count = vim.fn.strchars(str)
  local low, high = 0, char_count
  local best = ""
  while low <= high do
    local mid = math.floor((low + high) / 2)
    local part = vim.fn.strcharpart(str, 0, mid)
    if vim.fn.strdisplaywidth(part) <= target then
      best = part
      low = mid + 1
    else
      high = mid - 1
    end
  end
  return best .. ellipsis
end

--- Pad a string to the given display width (left or right align).
--- @param str string|any
--- @param width number|nil
--- @param align string|nil "left" or "right"
--- @return string
local function pad_display(str, width, align)
  if not width or width <= 0 then
    return tostring(str or "")
  end
  str = tostring(str or "")
  local truncated = truncate_to_display_width(str, width)
  local dw = vim.fn.strdisplaywidth(truncated)
  local pad = width - dw
  if pad <= 0 then
    return truncated
  end
  local spaces = string.rep(" ", pad)
  if align == "right" then
    return spaces .. truncated
  else
    return truncated .. spaces
  end
end

--- Extract the display value for one column from a bookmark.
--- Returns nil when the column should be omitted (source/db_index absent, or format returns nil).
--- @param bm Bookmark
--- @param col_config table Column configuration
--- @return string|nil
local function get_column_value(bm, col_config)
  if type(col_config.format) == "function" then
    local ok, val = pcall(col_config.format, bm)
    if ok then
      -- nil from format hides the column entirely
      if val == nil then
        return nil
      end
      return tostring(val)
    end
    return ""
  end

  local field = col_config.field or ""
  if field == "note" then
    return bm.note or ""
  elseif field == "file" then
    local file = bm.file or ""
    local path_fmt = col_config.path or "relative"
    if type(path_fmt) == "function" then
      local ok, val = pcall(path_fmt, file)
      return ok and tostring(val or "") or ""
    elseif path_fmt == "absolute" or path_fmt == "abs" or path_fmt == ":p" then
      return vim.fn.fnamemodify(file, ":p")
    elseif path_fmt == "basename" or path_fmt == "base" or path_fmt == ":t" then
      return vim.fn.fnamemodify(file, ":t")
    elseif path_fmt == "relative" or path_fmt == "rel" or path_fmt == ":." then
      return vim.fn.fnamemodify(file, ":.")
    else
      -- Treat as a fnamemodify modifier string
      return vim.fn.fnamemodify(file, tostring(path_fmt))
    end
  elseif field == "line" then
    return tostring(bm.line or "")
  elseif field == "col" then
    return tostring(bm.col or "")
  elseif field == "source" then
    return bm.source or nil
  elseif field == "index" or field == "db_index" then
    return bm.db_index and tostring(bm.db_index) or nil
  elseif field == "loc" then
    return string.format("%d:%d", bm.line or 0, bm.col or 0)
  else
    return tostring(bm[field] or "")
  end
end

--- Build a single display line for a bookmark according to the current display config.
--- Columns whose value is nil are omitted.
--- @param bm Bookmark
--- @param config table|nil
--- @return string
local function get_display_line(bm, config)
  local display = (config and config.display) or {}
  local columns = display.columns
  if not columns or #columns == 0 then
    -- Fallback default (should not happen if setup was called)
    columns = {
      { field = "note", width = 40 },
      { field = "file", width = 50, path = "relative" },
      { field = "line", width = 6,  align = "right" },
      { field = "col",  width = 4,  align = "right" },
    }
  end
  local sep = display.separator or "  "

  local parts = {}
  for _, col in ipairs(columns) do
    local val = get_column_value(bm, col)
    if val ~= nil then
      local padded = pad_display(val, col.width, col.align or "left")
      table.insert(parts, padded)
    end
  end
  return table.concat(parts, sep)
end

--- Build display line plus highlight ranges for columns that have an `hl` option.
--- Ranges are 0-based byte offsets into the resulting line.
--- @param bm Bookmark
--- @param config table|nil
--- @return string line
--- @return table[] highlights  list of {start, finish, group}
local function build_line_with_highlights(bm, config)
  local display = (config and config.display) or {}
  local columns = display.columns
  if not columns or #columns == 0 then
    columns = {
      { field = "note", width = 40 },
      { field = "file", width = 50, path = "relative" },
      { field = "line", width = 6,  align = "right" },
      { field = "col",  width = 4,  align = "right" },
    }
  end
  local sep = display.separator or "  "
  local sep_len = #sep

  local parts = {}
  local highlights = {}
  local pos = 0
  local first = true

  for _, col in ipairs(columns) do
    local val = get_column_value(bm, col)
    if val ~= nil then
      if not first then
        pos = pos + sep_len
      end
      first = false

      local padded = pad_display(val, col.width, col.align or "left")
      local start_pos = pos
      table.insert(parts, padded)
      pos = pos + #padded

      local group = get_hl_group(col.hl)
      if group then
        table.insert(highlights, { start = start_pos, finish = pos, group = group })
      end
    end
  end

  local line = table.concat(parts, sep)
  return line, highlights
end

--- Parse a filter string into scope and query.
--- Default scope is "note". Prefixes:
---   f: or p:  → path only
---   a: or *:  → all displayed fields
--- @param filter string|nil
--- @return string scope  "note"|"path"|"all"
--- @return string query
local function parse_filter(filter)
  if not filter or filter == "" then
    return "note", ""
  end
  local prefix, rest = filter:match("^([fFaApP%*%*]):(.*)$")
  if prefix then
    local p = prefix:lower()
    if p == "f" or p == "p" then
      return "path", rest
    elseif p == "a" or p == "*" then
      return "all", rest
    end
  end
  return "note", filter
end

--- Check whether a bookmark matches the given scope and query (plain substring, case-insensitive).
--- @param bm Bookmark
--- @param scope string
--- @param query string
--- @param config table|nil
--- @return boolean
local function bookmark_matches(bm, scope, query, config)
  if not query or query == "" then
    return true
  end
  local q = query:lower()
  if scope == "path" then
    return (bm.file or ""):lower():find(q, 1, true) ~= nil
  elseif scope == "all" then
    local line = get_display_line(bm, config)
    return line:lower():find(q, 1, true) ~= nil
  else
    -- default: note only
    return (bm.note or ""):lower():find(q, 1, true) ~= nil
  end
end

--- Apply column highlights to the buffer.
--- @param bufnr number
--- @param all_highlights table[][]  per-line list of highlight ranges
local function apply_highlights(bufnr, all_highlights)
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
  for line_idx, ranges in ipairs(all_highlights) do
    local lnum = line_idx - 1  -- 0-based
    for _, r in ipairs(ranges) do
      vim.api.nvim_buf_add_highlight(bufnr, hl_ns, r.group, lnum, r.start, r.finish)
    end
  end
end

--- Refresh the bookmark buffer with an optional filter string.
--- Filter supports prefixes: (none) = note, f:/p: = path, a:/*: = all fields.
--- @param bufnr number
--- @param bookmarks Bookmark[]
--- @param filter string|nil
local function refresh_buffer(bufnr, bookmarks, filter)
  local state = buffer_state[bufnr]
  local config = state and state.config or {}
  local scope, query = parse_filter(filter)
  local lines = {}
  local filtered = {}
  local all_highlights = {}
  for _, bm in ipairs(bookmarks) do
    if bookmark_matches(bm, scope, query, config) then
      local line, highlights = build_line_with_highlights(bm, config)
      table.insert(lines, line)
      table.insert(filtered, bm)
      table.insert(all_highlights, highlights)
    end
  end
  -- Temporarily make modifiable to update lines
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = was_modifiable
  apply_highlights(bufnr, all_highlights)
  buffer_state[bufnr].filtered = filtered
  buffer_state[bufnr].filter = filter or ""
  buffer_state[bufnr].filter_scope = scope
  buffer_state[bufnr].filter_query = query
  -- Update statusline on the window if we have one
  local win = buffer_state[bufnr].win
  if win and vim.api.nvim_win_is_valid(win) then
    local status
    local prefix = "Pen"
    if buffer_state[bufnr] and buffer_state[bufnr].is_all then
      prefix = "Pen All"
    end
    if filter and filter ~= "" then
      local scope_label = ({ note = "note", path = "path", all = "all" })[scope] or scope
      status = string.format("%s [%s: %s] (%d/%d)", prefix, scope_label, query, #filtered, #bookmarks)
    else
      status = string.format("%s (%d bookmarks)", prefix, #bookmarks)
    end
    vim.api.nvim_set_option_value("statusline", status, { win = win })
  end

  -- If preview is open, refresh it for the (possibly new) current item
  if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
    vim.schedule(function()
      update_preview(bufnr)
    end)
  end
end

--- Jump to the bookmark on the current line of the pen buffer.
--- Clamps line and column to valid ranges.
--- @param bufnr number
local function jump_to_bookmark(bufnr)
  local state = buffer_state[bufnr]
  if not state then return end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local bm = state.filtered[row]
  if not bm then return end

  if not bm.file then
    vim.notify("Cannot jump: missing file", vim.log.levels.WARN)
    return
  end

  -- oil:// and other scheme URLs are not regular files; allow them
  local is_scheme = bm.file:match("^%w+://")
  if not is_scheme and vim.fn.filereadable(bm.file) == 0 then
    vim.notify("Cannot jump: file not readable", vim.log.levels.WARN)
    return
  end

  -- Close the pen buffer first? Or switch. We'll switch to the file.
  local current_win = vim.api.nvim_get_current_win()
  -- Try to find existing window with the file, or open it
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_name(b) == bm.file then
      target_win = win
      break
    end
  end

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  else
    -- Prefer oil.open for oil:// URLs when available
    if bm.file:match("^oil://") then
      local ok, oil = pcall(require, "oil")
      if ok and oil.open then
        oil.open(bm.file)
      else
        vim.cmd("edit " .. vim.fn.fnameescape(bm.file))
      end
    else
      vim.cmd("edit " .. vim.fn.fnameescape(bm.file))
    end
  end

  -- Clamp line/col to valid range to avoid "Invalid cursor line: out of range"
  local target_buf = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(target_buf)
  if line_count < 1 then
    vim.notify("Target buffer has no lines", vim.log.levels.WARN)
    return
  end
  local line = math.min(math.max(1, bm.line or 1), line_count)
  local col = math.max(0, (bm.col or 1) - 1)  -- 0-based for nvim_win_set_cursor
  -- Clamp col to line length
  local line_text = vim.api.nvim_buf_get_lines(target_buf, line - 1, line, false)[1] or ""
  local max_col = #line_text
  col = math.min(col, max_col)

  local ok, err = pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
  if not ok then
    vim.notify("Failed to set cursor: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if line ~= bm.line then
    vim.notify(
      string.format("Bookmark line %d out of range (file has %d lines), jumped to line %d", bm.line, line_count, line),
      vim.log.levels.WARN)
  end
  vim.cmd("normal! zz")
  -- Optionally close the pen window if it was a split, but for now leave it
end

--- Update (or create) the floating preview for the bookmark under the cursor.
--- Does nothing if preview is not currently open.
--- @param bufnr number
local function update_preview(bufnr)
  local state = buffer_state[bufnr]
  if not state or not state.preview_win or not vim.api.nvim_win_is_valid(state.preview_win) then
    return
  end

  local win = state.win
  local row = 1
  if win and vim.api.nvim_win_is_valid(win) then
    row = vim.api.nvim_win_get_cursor(win)[1]
  else
    row = vim.api.nvim_win_get_cursor(0)[1]
  end

  local bm = state.filtered and state.filtered[row]
  local preview_buf = state.preview_buf
  if not preview_buf or not vim.api.nvim_buf_is_valid(preview_buf) then
    return
  end

  local function set_lines(lines)
    vim.bo[preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
    vim.bo[preview_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(preview_buf, -1, 0, -1)
  end

  if not bm or not bm.file then
    set_lines({ "Cannot preview: missing file" })
    vim.api.nvim_win_set_config(state.preview_win, { title = "Preview" })
    return
  end

  -- oil:// directory bookmarks: show a simple directory listing
  if bm.file:match("^oil://") then
    local real_path = bm.file:sub(7) -- strip "oil://"
    if real_path == "" then
      set_lines({ "Invalid oil:// path" })
      vim.api.nvim_win_set_config(state.preview_win, { title = "Preview" })
      return
    end
    if vim.fn.isdirectory(real_path) == 1 then
      local entries = vim.fn.readdir(real_path)
      if type(entries) ~= "table" then
        set_lines({ "Cannot list directory: " .. real_path })
        vim.api.nvim_win_set_config(state.preview_win, { title = "Preview" })
        return
      end
      table.sort(entries)
      local dir = real_path
      if not dir:match("/$") then
        dir = dir .. "/"
      end
      local preview_lines = {}
      for _, name in ipairs(entries) do
        local full = dir .. name
        local is_dir = vim.fn.isdirectory(full) == 1
        table.insert(preview_lines, name .. (is_dir and "/" or ""))
      end
      if #preview_lines == 0 then
        preview_lines = { "(empty directory)" }
      end
      set_lines(preview_lines)
      local display_name = real_path:gsub("/$", "")
      display_name = vim.fn.fnamemodify(display_name, ":t")
      vim.api.nvim_win_set_config(state.preview_win, {
        title = "Preview: " .. display_name .. "/",
      })
      return
    else
      set_lines({ "oil:// path is not a directory: " .. real_path })
      vim.api.nvim_win_set_config(state.preview_win, { title = "Preview" })
      return
    end
  end

  if bm.file:match("^%w+://") then
    set_lines({ "Preview not available for " .. (bm.file:match("^(%w+://)") or "scheme") })
    vim.api.nvim_win_set_config(state.preview_win, { title = "Preview" })
    return
  end

  if vim.fn.filereadable(bm.file) == 0 then
    set_lines({ "Cannot preview: file not readable" })
    vim.api.nvim_win_set_config(state.preview_win, { title = "Preview" })
    return
  end

  -- Read context around the line
  local context = state.preview_context or 5
  local lines = vim.fn.readfile(bm.file)
  local start_line = math.max(1, (bm.line or 1) - context)
  local end_line = math.min(#lines, (bm.line or 1) + context)
  local preview_lines = {}
  for i = start_line, end_line do
    table.insert(preview_lines, string.format("%4d | %s", i, lines[i] or ""))
  end

  set_lines(preview_lines)

  -- Highlight the target line (0-based)
  local highlight_line = bm.line - start_line
  if highlight_line >= 0 and highlight_line < #preview_lines then
    vim.api.nvim_buf_add_highlight(preview_buf, -1, "Search", highlight_line, 0, -1)
  end

  vim.api.nvim_win_set_config(state.preview_win, {
    title = string.format("Preview: %s:%d (±%d)", vim.fn.fnamemodify(bm.file, ":t"), bm.line, context),
  })
end

--- Toggle a floating preview window for the bookmark on the current line.
--- When enabled, the preview updates live as the cursor moves.
--- @param bufnr number
local function toggle_preview(bufnr)
  local state = buffer_state[bufnr]
  if not state then return end

  -- Close existing preview if any
  if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
    vim.api.nvim_win_close(state.preview_win, true)
    state.preview_win = nil
    state.preview_buf = nil
    if state.preview_augroup then
      vim.api.nvim_clear_autocmds({ group = state.preview_augroup })
      state.preview_augroup = nil
    end
    return
  end

  -- Create empty preview buffer/window first; content will be filled by update_preview
  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[preview_buf].filetype = "pen_preview"
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].buftype = "nofile"

  local width = 80
  local context = state.preview_context or 5
  local height = math.min(math.max(context * 2 + 3, 8), math.floor(vim.o.lines * 0.7))
  local row_pos = math.floor((vim.o.lines - height) / 2)
  local col_pos = math.floor((vim.o.columns - width) / 2)

  local preview_win = vim.api.nvim_open_win(preview_buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row_pos,
    col = col_pos,
    style = "minimal",
    border = "rounded",
    title = "Preview",
    title_pos = "center",
  })

  state.preview_win = preview_win
  state.preview_buf = preview_buf

  -- Live update on cursor move
  state.preview_augroup = vim.api.nvim_create_augroup("PenPreview_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.preview_augroup,
    buffer = bufnr,
    callback = function()
      update_preview(bufnr)
    end,
  })

  -- Auto-close preview when leaving the pen buffer
  vim.api.nvim_create_autocmd("BufLeave", {
    group = state.preview_augroup,
    buffer = bufnr,
    callback = function()
      if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
        vim.api.nvim_win_close(state.preview_win, true)
      end
      state.preview_win = nil
      state.preview_buf = nil
    end,
  })

  -- Initial content
  update_preview(bufnr)
end

--- Adjust the preview context size (lines before/after the bookmark).
--- Works even if preview is not currently open (value is stored for next open).
--- If preview is open, resizes the window and refreshes content immediately.
--- @param bufnr number
--- @param delta number positive to increase, negative to decrease
local function adjust_preview_context(bufnr, delta)
  local state = buffer_state[bufnr]
  if not state then return end
  local new_context = math.max(0, (state.preview_context or 5) + delta)
  if new_context == state.preview_context then return end
  state.preview_context = new_context

  if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
    local height = math.min(math.max(new_context * 2 + 3, 8), math.floor(vim.o.lines * 0.7))
    local row_pos = math.floor((vim.o.lines - height) / 2)
    vim.api.nvim_win_set_config(state.preview_win, {
      height = height,
      row = row_pos,
    })
    update_preview(bufnr)
  end

  -- Transient feedback (does not go into message history permanently in the same way)
  vim.api.nvim_echo({{ string.format("Preview context: ±%d", new_context), "Normal" }}, false, {})
end

--- Start an incremental (live) filter prompt for the bookmark list.
--- @param bufnr number
local function start_incremental_filter(bufnr)
  local state = buffer_state[bufnr]
  if not state then return end

  -- Close existing filter prompt if any
  if state.filter_win and vim.api.nvim_win_is_valid(state.filter_win) then
    vim.api.nvim_win_close(state.filter_win, true)
    state.filter_win = nil
  end

  local filter_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[filter_buf].buftype = "nofile"
  vim.bo[filter_buf].bufhidden = "wipe"
  vim.bo[filter_buf].swapfile = false
  vim.bo[filter_buf].modifiable = true
  vim.api.nvim_buf_set_lines(filter_buf, 0, -1, false, { state.filter or "" })

  local width = math.min(60, vim.o.columns - 4)
  local height = 1
  local row = vim.o.lines - 4
  local col = math.floor((vim.o.columns - width) / 2)

  local filter_win = vim.api.nvim_open_win(filter_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = "Filter  (note | f:/p: path | a:/*: all | <CR> ok | <Esc> clear)",
    title_pos = "center",
  })

  state.filter_win = filter_win
  state.filter_buf = filter_buf

  -- Move cursor to end and enter insert
  vim.api.nvim_win_set_cursor(filter_win, { 1, #(state.filter or "") })
  vim.cmd("startinsert!")

  local augroup = vim.api.nvim_create_augroup("PenFilter_" .. bufnr, { clear = true })

  local function update_filter()
    if not vim.api.nvim_buf_is_valid(filter_buf) then return end
    local lines = vim.api.nvim_buf_get_lines(filter_buf, 0, 1, false)
    local text = lines[1] or ""
    refresh_buffer(bufnr, state.bookmarks, text)
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = filter_buf,
    callback = update_filter,
  })

  -- Close filter on leave or <Esc>/<CR>
  local function close_filter(clear)
    -- Prevent re-entrancy from BufLeave
    if state._closing_filter then return end
    state._closing_filter = true

    if state.filter_win and vim.api.nvim_win_is_valid(state.filter_win) then
      vim.api.nvim_win_close(state.filter_win, true)
    end
    state.filter_win = nil
    state.filter_buf = nil
    vim.api.nvim_clear_autocmds({ group = augroup })
    if clear then
      refresh_buffer(bufnr, state.bookmarks, "")
    end
    -- Return focus to the pen buffer
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_set_current_buf(bufnr)
    end
    -- Leave insert mode so the user can immediately navigate / select
    -- (filter was opened with startinsert!)
    vim.cmd("stopinsert")

    state._closing_filter = nil
  end

  vim.keymap.set("i", "<Esc>", function() close_filter(true) end, { buffer = filter_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function() close_filter(true) end, { buffer = filter_buf, silent = true })
  vim.keymap.set("i", "<CR>", function() close_filter(false) end, { buffer = filter_buf, silent = true })
  vim.keymap.set("n", "<CR>", function() close_filter(false) end, { buffer = filter_buf, silent = true })

  -- Also close on BufLeave of the filter
  vim.api.nvim_create_autocmd("BufLeave", {
    group = augroup,
    buffer = filter_buf,
    callback = function() close_filter(false) end,
  })
end

--- Open the bookmark list for a given db_path index, or all if idx is nil.
--- @param idx number|nil
--- @param config table
function M.open(idx, config)
  local bookmarks = {}
  local path
  local bufname
  local is_all = false

  if idx == nil then
    -- Merge all
    for i, p in ipairs(config.db_path or {}) do
      local bms = require("pen.bookmark").load(p)
      local src = vim.fn.fnamemodify(p, ":t")
      for _, bm in ipairs(bms) do
        bm.source = src
        bm.db_index = i
        table.insert(bookmarks, bm)
      end
    end
    bufname = "pen://all"
    is_all = true
  else
    path = config.db_path[idx]
    if not path then
      vim.notify("No path for index " .. tostring(idx), vim.log.levels.ERROR)
      return
    end
    bookmarks = require("pen.bookmark").load(path)
    bufname = vim.fn.fnamemodify(path, ":t")
  end

  -- Create a new scratch buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  -- Set buffer name to the .pen filename (or pen://all) so it doesn't show as [No Name]
  pcall(vim.api.nvim_buf_set_name, bufnr, bufname)
  vim.bo[bufnr].filetype = "pen"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  -- Leave modifiable true initially for population

  buffer_state[bufnr] = {
    bookmarks = bookmarks,
    filtered = bookmarks,
    filter = "",
    path = path,
    idx = idx,
    is_all = is_all,
    config = config,
    preview_context = (config.preview and config.preview.context) or 5,
  }

  refresh_buffer(bufnr, bookmarks, "")

  -- Open in current window (replace current buffer, no split)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].modifiable = false
  buffer_state[bufnr].win = win

  -- Initial statusline (refresh_buffer already set it, but keep consistent)
  local prefix = is_all and "Pen All" or "Pen"
  local status = string.format("%s (%d bookmarks)", prefix, #bookmarks)
  vim.api.nvim_set_option_value("statusline", status, { win = win })

  -- Keymaps (buffer local)
  local opts = { buffer = bufnr, noremap = true, silent = true }
  vim.keymap.set("n", "<CR>", function() jump_to_bookmark(bufnr) end, opts)
  vim.keymap.set("n", "p", function() toggle_preview(bufnr) end, opts)
  vim.keymap.set("n", "}", function() adjust_preview_context(bufnr, 1) end, opts)
  vim.keymap.set("n", "{", function() adjust_preview_context(bufnr, -1) end, opts)
  vim.keymap.set("n", "/", function() start_incremental_filter(bufnr) end, opts)
  vim.keymap.set("n", "q", function()
    -- close preview if open
    local state = buffer_state[bufnr]
    if state and state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
      vim.api.nvim_win_close(state.preview_win, true)
    end
    if state and state.preview_augroup then
      vim.api.nvim_clear_autocmds({ group = state.preview_augroup })
      state.preview_augroup = nil
    end
    -- close filter prompt if open
    if state and state.filter_win and vim.api.nvim_win_is_valid(state.filter_win) then
      vim.api.nvim_win_close(state.filter_win, true)
    end
    -- Delete the scratch buffer (switches back to previous buffer)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    -- clear filter if any
    local state = buffer_state[bufnr]
    if state and state.filter ~= "" then
      refresh_buffer(bufnr, state.bookmarks, "")
    end
  end, opts)
  vim.keymap.set("n", "<C-e>", function()
    -- Open the corresponding .pen file for editing
    local state = buffer_state[bufnr]
    if not state then return end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local bm = state.filtered[row]
    if not bm then return end

    local path_to_edit
    if state.is_all then
      if bm.db_index and state.config and state.config.db_path then
        path_to_edit = state.config.db_path[bm.db_index]
      end
    else
      path_to_edit = state.path
    end

    if not path_to_edit or path_to_edit == "" then
      vim.notify("Cannot determine .pen file to edit", vim.log.levels.WARN)
      return
    end

    -- Close floating windows if open
    if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
      vim.api.nvim_win_close(state.preview_win, true)
    end
    if state.filter_win and vim.api.nvim_win_is_valid(state.filter_win) then
      vim.api.nvim_win_close(state.filter_win, true)
    end

    vim.cmd("edit " .. vim.fn.fnameescape(path_to_edit))
  end, opts)

  -- Cleanup on buf delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = bufnr,
    callback = function()
      local state = buffer_state[bufnr]
      if state then
        if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
          vim.api.nvim_win_close(state.preview_win, true)
        end
        if state.preview_augroup then
          vim.api.nvim_clear_autocmds({ group = state.preview_augroup })
        end
        if state.filter_win and vim.api.nvim_win_is_valid(state.filter_win) then
          vim.api.nvim_win_close(state.filter_win, true)
        end
      end
      buffer_state[bufnr] = nil
    end,
  })

  -- Auto-open preview if configured (default true)
  local preview_cfg = config.preview or {}
  if preview_cfg.auto_open ~= false then
    toggle_preview(bufnr)
  end

  if is_all then
    vim.notify(string.format("Opened all pen bookmarks (%d)", #bookmarks), vim.log.levels.INFO)
  else
    vim.notify("Opened pen bookmarks: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
  end
end

--- List all configured db_path files and allow jumping to edit them.
--- @param config table Plugin configuration
function M.list(config)
  local paths = config.db_path or {}
  if #paths == 0 then
    vim.notify("No db_path configured", vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, bufnr, "pen://list")
  vim.bo[bufnr].filetype = "pen"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true

  local lines = {}
  for i, path in ipairs(paths) do
    local display = string.format("%2d  %s", i, path)
    table.insert(lines, display)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  -- Open in a split
  vim.cmd("split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_buf(bufnr)

  local status = string.format("PenLs (%d files)", #paths)
  vim.api.nvim_set_option_value("statusline", status, { win = win })

  -- Keymaps
  local opts = { buffer = bufnr, noremap = true, silent = true }
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local path = paths[row]
    if path then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end
  end, opts)
  vim.keymap.set("n", "q", function()
    vim.cmd("close")
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    vim.cmd("close")
  end, opts)

  vim.notify("Listed " .. #paths .. " pen files. <CR> to edit, q to close", vim.log.levels.INFO)
end

return M

