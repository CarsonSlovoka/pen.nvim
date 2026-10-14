local M = {}

-- Store state per buffer
local buffer_state = {}

local function get_display_line(bm)
  local filename = vim.fn.fnamemodify(bm.file, ":t")
  local rel = vim.fn.fnamemodify(bm.file, ":.")
  if #rel > 60 then
    rel = "..." .. rel:sub(-57)
  end
  local prefix = ""
  if bm.source then
    prefix = string.format("[%s] ", bm.source)
  end
  return string.format("%s%s:%d:%d  %s", prefix, filename, bm.line, bm.col, bm.note or "")
end

local function refresh_buffer(bufnr, bookmarks, filter)
  local lines = {}
  local filtered = {}
  for _, bm in ipairs(bookmarks) do
    local line = get_display_line(bm)
    if not filter or filter == "" or line:lower():find(filter:lower(), 1, true) then
      table.insert(lines, line)
      table.insert(filtered, bm)
    end
  end
  -- Temporarily make modifiable to update lines
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = was_modifiable
  buffer_state[bufnr].filtered = filtered
  buffer_state[bufnr].filter = filter or ""
  -- Update statusline on the window if we have one
  local win = buffer_state[bufnr].win
  if win and vim.api.nvim_win_is_valid(win) then
    local status
    local prefix = "Pen"
    if buffer_state[bufnr] and buffer_state[bufnr].is_all then
      prefix = "Pen All"
    end
    if filter and filter ~= "" then
      status = string.format("%s [filter: %s] (%d/%d)", prefix, filter, #filtered, #bookmarks)
    else
      status = string.format("%s (%d bookmarks)", prefix, #bookmarks)
    end
    vim.api.nvim_set_option_value("statusline", status, { win = win })
  end
end

--- Jump to the bookmark on the current line
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
  local col = math.max(0, (bm.col or 1) - 1)
  local line_text = vim.api.nvim_buf_get_lines(target_buf, line - 1, line, false)[1] or ""
  col = math.min(col, #line_text)

  local ok, err = pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
  if not ok then
    vim.notify("Failed to set cursor: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if line ~= bm.line then
    vim.notify(string.format("Bookmark line %d out of range (file has %d lines), jumped to line %d", bm.line, line_count, line), vim.log.levels.WARN)
  end
  vim.cmd("normal! zz")
  -- Optionally close the pen window if it was a split, but for now leave it
end

--- Toggle preview of the current bookmark
local function toggle_preview(bufnr)
  local state = buffer_state[bufnr]
  if not state then return end

  -- Close existing preview if any
  if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
    vim.api.nvim_win_close(state.preview_win, true)
    state.preview_win = nil
    state.preview_buf = nil
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local bm = state.filtered[row]
  if not bm or not bm.file then
    vim.notify("Cannot preview: missing file", vim.log.levels.WARN)
    return
  end

  -- oil:// and other scheme URLs cannot be previewed with readfile
  if bm.file:match("^%w+://") then
    vim.notify("Preview not available for " .. bm.file:match("^(%w+://)"), vim.log.levels.WARN)
    return
  end

  if vim.fn.filereadable(bm.file) == 0 then
    vim.notify("Cannot preview: file not readable", vim.log.levels.WARN)
    return
  end

  -- Read context around the line (5 before, 5 after)
  local lines = vim.fn.readfile(bm.file)
  local start_line = math.max(1, bm.line - 5)
  local end_line = math.min(#lines, bm.line + 5)
  local preview_lines = {}
  for i = start_line, end_line do
    table.insert(preview_lines, string.format("%4d | %s", i, lines[i] or ""))
  end

  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, preview_lines)
  vim.bo[preview_buf].filetype = "pen_preview"
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].buftype = "nofile"

  -- Highlight the target line (relative)
  local highlight_line = bm.line - start_line -- 0-based in buffer? Wait, nvim_buf_add_highlight is 0-based
  vim.api.nvim_buf_add_highlight(preview_buf, -1, "Search", highlight_line, 0, -1)

  local width = 80
  local height = math.min(15, #preview_lines + 2)
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
    title = "Preview: " .. vim.fn.fnamemodify(bm.file, ":t") .. ":" .. bm.line,
    title_pos = "center",
  })

  state.preview_win = preview_win
  state.preview_buf = preview_buf

  -- Auto-close preview when leaving or on next action? For now, toggle handles it.
  -- Also close on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = bufnr,
    once = true,
    callback = function()
      if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
        vim.api.nvim_win_close(state.preview_win, true)
      end
    end,
  })
end

--- Start incremental filter (real-time as you type)
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
    title = "Filter  (type to filter live, <CR> confirm, <Esc> clear)",
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
    local input = vim.api.nvim_buf_get_lines(filter_buf, 0, 1, false)[1] or ""
    refresh_buffer(bufnr, state.bookmarks, input)
    -- Keep list cursor on first match if any
    local list_win = state.win
    if list_win and vim.api.nvim_win_is_valid(list_win) and #(state.filtered or {}) > 0 then
      pcall(vim.api.nvim_win_set_cursor, list_win, { 1, 0 })
    end
  end

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = augroup,
    buffer = filter_buf,
    callback = update_filter,
  })

  local function close_filter(keep)
    if vim.api.nvim_win_is_valid(filter_win) then
      vim.api.nvim_win_close(filter_win, true)
    end
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    state.filter_win = nil
    state.filter_buf = nil
    if not keep then
      refresh_buffer(bufnr, state.bookmarks, "")
    end
    -- Return focus to the list window
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    vim.cmd("stopinsert")
  end

  local fopts = { buffer = filter_buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set({ "i", "n" }, "<CR>", function() close_filter(true) end, fopts)
  vim.keymap.set({ "i", "n" }, "<Esc>", function() close_filter(false) end, fopts)
  vim.keymap.set("n", "q", function() close_filter(true) end, fopts)

  -- Initial update in case default is non-empty
  update_filter()
end

--- Open the pen buffer for the given index, or all bookmarks if idx is nil
--- @param idx number|nil
--- @param config table
function M.open(idx, config)
  local bookmarks
  local bufname
  local path = nil
  local is_all = false

  if not idx then
    -- Merge bookmarks from all configured db_path
    bookmarks = {}
    for _, p in ipairs(config.db_path or {}) do
      local bms = require("pen.bookmark").load(p)
      local src = vim.fn.fnamemodify(p, ":t")
      for _, bm in ipairs(bms) do
        bm.source = src
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
  vim.keymap.set("n", "/", function() start_incremental_filter(bufnr) end, opts)
  vim.keymap.set("n", "q", function()
    -- close preview if open
    local state = buffer_state[bufnr]
    if state and state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
      vim.api.nvim_win_close(state.preview_win, true)
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

  -- Cleanup on buf delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = bufnr,
    callback = function()
      local state = buffer_state[bufnr]
      if state then
        if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
          vim.api.nvim_win_close(state.preview_win, true)
        end
        if state.filter_win and vim.api.nvim_win_is_valid(state.filter_win) then
          vim.api.nvim_win_close(state.filter_win, true)
        end
      end
      buffer_state[bufnr] = nil
    end,
  })

  if is_all then
    vim.notify(string.format("Opened all pen bookmarks (%d)", #bookmarks), vim.log.levels.INFO)
  else
    vim.notify("Opened pen bookmarks: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.INFO)
  end
end

--- List all configured db_path files and allow jumping to edit them
--- @param config table
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
