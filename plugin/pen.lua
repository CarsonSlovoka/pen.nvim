-- pen.nvim plugin entry (optional early loading)
-- Main setup is expected to be called by the user via require("pen").setup()

if vim.g.loaded_pen_nvim then
  return
end
vim.g.loaded_pen_nvim = true

-- Filetype detection is registered in setup(), but we can also do a basic one here
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.pen",
  callback = function()
    if vim.bo.filetype == "" then
      vim.bo.filetype = "pen"
    end
  end,
})
