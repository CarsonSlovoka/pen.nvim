--- pen.nvim main module
--- Provides setup and configuration for the pen bookmark plugin.
local M = {}

--- Default configuration.
--- @type table
local config = {
  db_path = {},
  display = {
    columns = {
      { field = "index",  width = 4,  align = "right",  hl = "Comment" }, -- 僅在 :PenOpen（無 index）時有值
      { field = "source", width = 16, hl = "Comment" },                   -- 僅在 :PenOpen（無 index）時有值
      { field = "note",   width = 40 },
      { field = "file",   width = 15, path = ":t",      hl = { fg = "#88ccff", italic = true } },
      { field = "file",   width = 60, path = "relative" }, -- absolute (:p), basename (:t), relative (:.)
      { field = "line",   width = 6,  align = "right",  hl = "Comment" },
      { field = "col",    width = 4,  align = "right",  hl = "Comment" },
    },
    separator = "  ",
  },
}

--- Setup the pen.nvim plugin.
--- Registers user commands and applies configuration.
--- @param opts table|nil Configuration options. Expected keys:
---   - db_path: list of string paths to .pen/.tsv files (required, non-empty)
---   - display: optional table controlling column display in PenOpen
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", config, opts)

  if type(config.db_path) ~= "table" or #config.db_path == 0 then
    vim.notify("pen.nvim: db_path must be a non-empty table of paths", vim.log.levels.ERROR)
    return
  end

  -- Ensure directories exist
  for _, path in ipairs(config.db_path) do
    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
  end

  -- Create user commands
  vim.api.nvim_create_user_command("PenAdd", function(cmd_opts)
    local args = vim.split(cmd_opts.args, "%s+", { trimempty = true })
    if #args < 1 then
      vim.notify("Usage: :PenAdd <index> [note]", vim.log.levels.ERROR)
      return
    end
    local idx = tonumber(args[1])
    if not idx or idx < 1 or idx > #config.db_path then
      vim.notify("Invalid bookmark index: " .. tostring(args[1]), vim.log.levels.ERROR)
      return
    end
    local note = nil
    if #args > 1 then
      note = table.concat(args, " ", 2)
    end
    require("pen.bookmark").add(idx, note, config)
  end, {
    nargs = "+",
    desc = "Add current position to a pen bookmark file",
    complete = function(arglead, cmdline, cursorpos)
      -- Simple completion for index
      local indices = {}
      for i = 1, #config.db_path do
        table.insert(indices, tostring(i))
      end
      return indices
    end,
  })

  vim.api.nvim_create_user_command("PenOpen", function(cmd_opts)
    -- Omit index to open merged view of all db_path
    if not cmd_opts.args or cmd_opts.args == "" then
      require("pen.ui").open(nil, config)
      return
    end
    local idx = tonumber(cmd_opts.args)
    if not idx or idx < 1 or idx > #config.db_path then
      vim.notify("Invalid bookmark index: " .. tostring(cmd_opts.args), vim.log.levels.ERROR)
      return
    end
    require("pen.ui").open(idx, config)
  end, {
    nargs = "?",
    desc = "Open a pen bookmark buffer (omit index to merge all)",
    complete = function(arglead, cmdline, cursorpos)
      local indices = {}
      for i = 1, #config.db_path do
        table.insert(indices, tostring(i))
      end
      return indices
    end,
  })

  vim.api.nvim_create_user_command("PenLs", function()
    require("pen.ui").list(config)
  end, {
    nargs = 0,
    desc = "List configured db_path files and jump to edit them",
  })

  -- Filetype detection for .pen files
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*.pen",
    callback = function()
      vim.bo.filetype = "pen"
    end,
  })
end

--- Get the current configuration (intended for internal / keymap use).
--- @return table Current config table
function M.get_config()
  return config
end

return M
