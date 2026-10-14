local M = {}

local config = {
  db_path = {},
}

--- Setup the pen.nvim plugin.
--- @param opts table|nil Configuration options. Expected: db_path (list of string paths to .pen files)
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
    local idx = tonumber(cmd_opts.args)
    if not idx or idx < 1 or idx > #config.db_path then
      vim.notify("Invalid bookmark index: " .. tostring(cmd_opts.args), vim.log.levels.ERROR)
      return
    end
    require("pen.ui").open(idx, config)
  end, {
    nargs = 1,
    desc = "Open a pen bookmark buffer",
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

--- Get the current config (for internal use)
function M.get_config()
  return config
end

return M
