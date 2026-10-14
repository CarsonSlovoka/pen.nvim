local M = {}

--- Default note is the filename of the current buffer
local function get_default_note()
  local filename = vim.fn.expand("%:t")
  if filename == "" then
    return "untitled"
  end
  return filename
end

--- Parse location string "file:line:col" (handles paths with colons by taking last two numbers)
local function parse_location(loc)
  local file, line, col = loc:match("^(.*):(%d+):(%d+)$")
  if file and line and col then
    return file, tonumber(line), tonumber(col)
  end
  return nil, nil, nil
end

--- Load bookmarks from a .pen file (TSV format: note\tfile:line:col)
--- @param path string
--- @return table list of bookmarks
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

--- Save bookmarks to a .pen file (TSV)
--- @param path string
--- @param bookmarks table
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

--- Add current cursor position to the specified bookmark file
--- @param idx number
--- @param note string|fun():string|nil
--- @param config table
function M.add(idx, note, config)
  local path = config.db_path[idx]
  if not path then
    vim.notify("No path configured for index " .. idx, vim.log.levels.ERROR)
    return
  end

  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("No file associated with current buffer", vim.log.levels.WARN)
    return
  end

  local line = vim.fn.line(".")
  local col = vim.fn.col(".")

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
