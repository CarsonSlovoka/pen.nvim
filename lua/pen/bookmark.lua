--- pen.nvim bookmark module
--- Handles loading, saving, and adding bookmarks in TSV format (note\tfile:line:col).

--- @class Bookmark
--- @field file string Absolute path, oil:// URL, or other scheme URL
--- @field line number 1-based line number
--- @field col number 1-based column number
--- @field note string User-provided note
--- @field source string|nil Basename of the source .pen file (only set in merged view)

local M = {}

--- Get a default note from the current buffer's filename.
--- @return string
local function get_default_note()
  local filename = vim.fn.expand("%:t")
  if filename == "" then
    return "untitled"
  end
  return filename
end

--- Parse a location string of the form "file:line:col".
--- Handles paths that contain colons by matching the last two numeric components.
--- @param loc string
--- @return string|nil file
--- @return number|nil line
--- @return number|nil col
local function parse_location(loc)
  local file, line, col = loc:match("^(.*):(%d+):(%d+)$")
  if file and line and col then
    return file, tonumber(line), tonumber(col)
  end
  return nil, nil, nil
end

--- Load bookmarks from a .pen (TSV) file.
--- @param path string Absolute path to the bookmark file
--- @return Bookmark[] List of bookmarks
function M.load(path)
  local bookmarks = {}
  if vim.fn.filereadable(path) == 0 then
    return bookmarks
  end
  local lines = vim.fn.readfile(path)
  for _, line in ipairs(lines) do
    if line ~= "" then
      local note, loc = line:match("^(.-)\t(.*)$")
      if note and loc then
        local file, line_num, col = parse_location(loc)
        if file and line_num and col then
          table.insert(bookmarks, {
            file = file,
            line = line_num,
            col = col,
            note = note,
          })
        end
      end
    end
  end
  return bookmarks
end

--- Save bookmarks to a .pen (TSV) file.
--- Tabs inside notes are replaced with spaces to preserve the format.
--- @param path string Absolute path to the bookmark file
--- @param bookmarks Bookmark[] List of bookmarks
function M.save(path, bookmarks)
  local lines = {}
  for _, bm in ipairs(bookmarks) do
    local note = bm.note or ""
    -- Replace tabs in note to avoid breaking TSV
    note = note:gsub("\t", " ")
    local loc = string.format("%s:%d:%d", bm.file, bm.line, bm.col)
    table.insert(lines, note .. "\t" .. loc)
  end
  vim.fn.writefile(lines, path)
end

--- Resolve the best location to bookmark from the current buffer.
--- For oil.nvim buffers, prefers the real path of the entry under the cursor.
--- @return string|nil file
--- @return number line
--- @return number col
local function resolve_current_location()
  local bufname = vim.api.nvim_buf_get_name(0)
  local ft = vim.bo.filetype

  -- Special handling for oil.nvim
  if ft == "oil" or bufname:match("^oil://") then
    local ok, oil = pcall(require, "oil")
    if ok and oil.get_cursor_entry and oil.get_current_dir then
      local entry = oil.get_cursor_entry()
      local dir = oil.get_current_dir()
      if entry and dir then
        local name = entry.name or ""
        if entry.type == "directory" then
          -- Ensure trailing slash for directories
          if not name:match("/$") then
            name = name .. "/"
          end
        end
        local real_path = dir .. name
        -- For files, store the real filesystem path so jump opens the file directly.
        -- For directories, store an oil:// URL so jump reopens oil on that directory.
        if entry.type == "file" then
          return real_path, 1, 1
        else
          -- oil:// + absolute path (oil expects the protocol form)
          local oil_url = "oil://" .. real_path
          return oil_url, 1, 1
        end
      end
    end
    -- Fallback: still record the oil buffer itself if oil API failed
  end

  -- Normal buffer
  local file = vim.fn.expand("%:p")
  if file == "" then
    return nil
  end
  return file, vim.fn.line("."), vim.fn.col(".")
end

--- Add the current cursor position to the specified bookmark file.
--- @param idx number Index into config.db_path (1-based)
--- @param note string|fun():string|nil Optional note; if a function, it is called to obtain the note
--- @param config table Plugin configuration table
function M.add(idx, note, config)
  local path = config.db_path[idx]
  if not path then
    vim.notify("No path configured for index " .. idx, vim.log.levels.ERROR)
    return
  end

  local file, line, col = resolve_current_location()
  if not file then
    vim.notify("No file associated with current buffer", vim.log.levels.WARN)
    return
  end

  -- Support note as a function (e.g. for interactive input in keymaps)
  if type(note) == "function" then
    note = note()
  end
  note = note or get_default_note()

  local bookmarks = M.load(path)
  table.insert(bookmarks, {
    file = file,
    line = line,
    col = col,
    note = note,
  })

  M.save(path, bookmarks)
  vim.notify(string.format("Added bookmark to %s: %s:%d:%d [%s]", vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(file, ":t"), line, col, note), vim.log.levels.INFO)
end

return M
