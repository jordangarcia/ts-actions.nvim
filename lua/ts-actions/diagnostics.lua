local event = require("nui.utils.autocmd").event
local Line = require("nui.line")
local Popup = require("nui.popup")
local Text = require("nui.text")
local lsp2 = require("ts-actions.lsp2")

local Diagnostics = {}
Diagnostics.__index = Diagnostics

function Diagnostics.new(options)
  local self = setmetatable({}, Diagnostics)
  self.options = vim.tbl_deep_extend("force", {
    dismiss_keys = { "<C-c>", "q" },
  }, options or {})
  self.popup = nil
  self.keymaps = {}
  self.autocmd_group = nil
  return self
end

function Diagnostics:goto_next_and_show(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR

  local check_cursor = not self.popup

  local next_diagnostic = lsp2.get_next({ severity = severity, check_cursor = check_cursor })

  if next_diagnostic then
    vim.api.nvim_win_set_cursor(0, { next_diagnostic.lnum + 1, next_diagnostic.col })
    self:show(next_diagnostic)
  else
    vim.notify("No more diagnostics found", vim.log.levels.INFO)
    self:close()
  end
end

function Diagnostics:show(diagnostic)
  if self.popup then
    self:close()
  end

  self.main_buf = vim.api.nvim_get_current_buf()

  local severity, style
  if diagnostic.severity == vim.diagnostic.severity.ERROR then
    severity = "Error"
  elseif diagnostic.severity == vim.diagnostic.severity.WARN then
    severity = "Warn"
  elseif diagnostic.severity == vim.diagnostic.severity.INFO then
    severity = "Info"
  elseif diagnostic.severity == vim.diagnostic.severity.HINT then
    severity = "Hint"
  else
    severity = "Info"
  end
  local highlight = "Diagnostic" .. severity

  local content = Line()
  content:append(Text(diagnostic.message, highlight))
  content:append(" ") -- Add a space between the two parts

  -- Add source and code if available
  if diagnostic.source or diagnostic.code then
    local source_code_str = ""
    if diagnostic.source then
      source_code_str = diagnostic.source
    end
    if diagnostic.code then
      if diagnostic.source then
        source_code_str = source_code_str .. " "
      end
      source_code_str = source_code_str .. "[" .. tostring(diagnostic.code) .. "]"
    end
    content:append(Text(source_code_str, "Comment"))
  end

  self.popup = Popup({
    size = { width = 50, height = 10 },
    position = { row = 2, col = 1 },
    enter = false,
    focusable = true,
    zindex = 50,
    relative = "cursor",
    border = {
      padding = { top = 0, bottom = 0, left = 1, right = 1 },
      style = "rounded",
      text = {
        top = Text(severity, highlight),
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      -- winblend = 0,
      winhighlight = string.format("Normal:%s,FloatBorder:%s", highlight, highlight),
    },
  })
  self.popup:mount()

  content:render(self.popup.bufnr, -1, 1)

  self:setup_autocmds()
  self:setup_keymaps()
  -- Close popup when cursor leaves the window
  self.popup:on(event.BufLeave, function()
    self:close()
  end)
end

function Diagnostics:setup_autocmds()
  self.main_buf_autocmd_group = vim.api.nvim_create_augroup("MainBufAutoClose", { clear = true })
  local close_autocmds = { "CursorMoved", "InsertEnter" }
  vim.defer_fn(function()
    vim.api.nvim_create_autocmd(close_autocmds, {
      group = self.main_buf_autocmd_group,
      buffer = self.main_buf,
      once = true,
      callback = function(args)
        self:close()
        vim.api.nvim_del_autocmd(args.id)
      end,
    })
  end, 0)

  -- Close popup on various events
  self.main_buf_autocmd_group = vim.api.nvim_create_augroup("PopupAutoClose" .. self.popup.bufnr, { clear = true })
  self.autocmd_group = vim.api.nvim_create_augroup("PopupAutoClose" .. self.popup.bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ "BufHidden", "InsertCharPre", "WinLeave", "FocusLost" }, {
    group = self.autocmd_group,
    buffer = self.popup.bufnr,
    once = true,
    callback = function()
      self:close()
    end,
  })
end

function Diagnostics:setup_keymaps()
  -- Set key mappings to dismiss the popup in the current window
  local current_win = vim.api.nvim_get_current_win()
  for _, key in ipairs(self.options.dismiss_keys) do
    vim.keymap.set({ "n", "v" }, key, function()
      self:close()
    end, { noremap = true, silent = true, buffer = vim.api.nvim_win_get_buf(current_win) })
    table.insert(self.keymaps, { key = key, mode = { "n", "v" }, buf = vim.api.nvim_win_get_buf(current_win) })
  end
end

function Diagnostics:close()
  -- Clean up keymaps
  for _, keymap in ipairs(self.keymaps) do
    vim.keymap.del(keymap.mode, keymap.key, { buffer = keymap.buf })
  end
  self.keymaps = {}

  -- Clean up autocommands
  if self.autocmd_group then
    pcall(vim.api.nvim_del_autocmd, self.autocmd_group)
    self.autocmd_group = nil
  end

  if self.main_buf_autocmd_group then
    pcall(vim.api.nvim_del_autocmd, self.main_buf_autocmd_group)
    self.main_buf_autocmd_group = nil
  end

  if self.popup then
    self.popup:unmount()
    self.popup = nil
  end
end

return Diagnostics.new()
