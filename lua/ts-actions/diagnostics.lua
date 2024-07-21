local event = require("nui.utils.autocmd").event
local Line = require("nui.line")
local Popup = require("nui.popup")
local Text = require("nui.text")
local keys = require("ts-actions.keys")
local lsp2 = require("ts-actions.lsp2")

local Diagnostics = {}
Diagnostics.__index = Diagnostics

local function concat_tables(...)
  local result = {}
  for _, t in ipairs({ ... }) do
    vim.list_extend(result, t)
  end
  return result
end

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

local function parse_severity(severity)
  local title = "Hint"
  if severity == vim.diagnostic.severity.ERROR then
    title = "Error"
  elseif severity == vim.diagnostic.severity.WARN then
    title = "Warn"
  elseif severity == vim.diagnostic.severity.INFO then
    title = "Info"
  end

  local highlight = "Diagnostic" .. title
  return title, highlight
end

local function make_diagnostic_lines(diagnostic, title, highlight, code_actions)
  -- vim.notify(vim.inspect(code_actions))

  local title_line = Line()
  -- title_line:append(Text(title, highlight))
  -- Add source and code if available
  if diagnostic.source or diagnostic.code then
    -- title_line:append(" ") -- Add a space between the two parts
    local source_code_str = ""
    if diagnostic.source then
      source_code_str = diagnostic.source
    end
    if diagnostic.code then
      if diagnostic.source then
        source_code_str = source_code_str .. " "
      end
      source_code_str = source_code_str
        .. "["
        .. tostring(diagnostic.code)
        .. "]"
    end
    -- title_line:append(Text(source_code_str, "Comment"))
    title_line:append(Text(source_code_str, highlight))
  end

  local lines = {}

  ---@type string[]
  local diag_lines = vim.split(diagnostic.message, "\n", { trimempty = true })

  local width = 0
  for i, content in ipairs(diag_lines) do
    local line = Line()
    line:append(Text(content:gsub("\r", ""), highlight))

    local line_width = vim.fn.strdisplaywidth(line:content())
    width = math.max(line_width, width)
    lines[i] = line
  end

  local KEYS = vim.split(
    "qwertyuiopasdfghlzxcvbnm" --[=[@as string]=],
    "",
    { trimempty = true }
  )
  -- handle code actions
  local used_keys = {}
  ---@type {name: string, key: string, item: any, order: integer}[]}
  local options = {}
  local code_action_lines = {}
  for i, action in ipairs(code_actions) do
    if action.command.title then
      local name = action.command.title
      local option = { item = action, order = 0, name = name }
      local match = assert(
        keys.get_action_config({
          title = option.name,
          priorities = {},
          valid_keys = KEYS,
          invalid_keys = used_keys,
          override_function = function(_) end,
        }),
        'Failed to find a key to map to "' .. option.name .. '"'
      )
      option.key = match.key
      option.order = match.order
      options[i] = option

      local line = Line()
      line:append(Text(string.format("[", i), "CodeActionNormal"))
      line:append(Text(string.format("%s", match.key), "CodeActionShortcut"))
      line:append(Text(string.format("] ", i), "CodeActionNormal"))
      line:append(Text(action.command.title, "CodeActionNormal"))
      code_action_lines[i] = line
      local line_width = vim.fn.strdisplaywidth(line:content())
      width = math.max(line_width, width)
    end
  end

  table.sort(options, function(a, b)
    return a.order < b.order
  end)

  if #code_action_lines == 0 then
    return title_line, lines, options, width, #lines
  end

  local divider = Line()
  divider:append(Text(string.rep("-", width), "Comment"))
  local divider_lines = { divider }

  local all_lines = concat_tables(lines, divider_lines, code_action_lines)

  return title_line, all_lines, options, width, #all_lines
end

function Diagnostics:goto_next_and_show(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR

  local check_cursor = not self.popup

  local next_diagnostic =
    lsp2.get_next({ severity = severity, check_cursor = check_cursor })

  if next_diagnostic then
    vim.api.nvim_win_set_cursor(
      0,
      { next_diagnostic.lnum + 1, next_diagnostic.col }
    )
    self:show(next_diagnostic)
  else
    self:close()
  end
end

function Diagnostics:show(diagnostic)
  if self.popup then
    self:close()
  end

  local code_actions = lsp2.code_action({ diagnostic })
  local severity, highlight = parse_severity(diagnostic.severity)
  self.main_buf = vim.api.nvim_get_current_buf()

  local title_line, contents, options, width, height =
    make_diagnostic_lines(diagnostic, severity, highlight, code_actions)

  self.popup = Popup({
    size = { width = width, height = height },
    position = { row = 2, col = 1 },
    enter = false,
    focusable = true,
    zindex = 50,
    relative = "cursor",
    border = {
      padding = { top = 0, bottom = 0, left = 0, right = 0 },
      style = "rounded",
      text = {
        top = title_line,
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      -- winblend = 0,
      winhighlight = string.format(
        "Normal:%s,FloatBorder:%s",
        "Normal",
        highlight
      ),
    },
  })
  self.popup:mount()

  for i, content in ipairs(contents) do
    content:render(self.popup.bufnr, -1, i)
  end

  self:setup_autocmds()
  self:setup_keymaps(options)
  -- Close popup when cursor leaves the window
  self.popup:on(event.BufLeave, function()
    self:close()
  end)
end

function Diagnostics:setup_autocmds()
  self.main_buf_autocmd_group =
    vim.api.nvim_create_augroup("MainBufAutoClose", { clear = true })
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
  self.main_buf_autocmd_group = vim.api.nvim_create_augroup(
    "PopupAutoClose" .. self.popup.bufnr,
    { clear = true }
  )
  self.autocmd_group = vim.api.nvim_create_augroup(
    "PopupAutoClose" .. self.popup.bufnr,
    { clear = true }
  )
  vim.api.nvim_create_autocmd(
    { "BufHidden", "InsertCharPre", "WinLeave", "FocusLost" },
    {
      group = self.autocmd_group,
      buffer = self.popup.bufnr,
      once = true,
      callback = function()
        self:close()
      end,
    }
  )
end

function Diagnostics:setup_keymaps(options)
  -- Set key mappings to dismiss the popup in the current window
  local current_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(current_win)
  for _, key in ipairs(self.options.dismiss_keys) do
    vim.keymap.set({ "n", "v" }, key, function()
      self:close()
    end, {
      noremap = true,
      silent = true,
      buffer = bufnr,
    })
    table.insert(self.keymaps, {
      key = key,
      mode = { "n", "v" },
      buf = bufnr,
    })
  end

  for i, option in ipairs(options) do
    vim.keymap.set("n", option.key, function()
      lsp2.execute_command(option.item)
      self:close()
    end, {
      buffer = bufnr,
      noremap = true,
      silent = true,
      nowait = true,
    })
    table.insert(self.keymaps, {
      key = option.key,
      mode = { "n" },
      buf = bufnr,
    })
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
    pcall(vim.api.nvim_del_augroup_by_id, self.autocmd_group)
    self.autocmd_group = nil
  end

  if self.main_buf_autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, self.main_buf_autocmd_group)
    self.main_buf_autocmd_group = nil
  end

  if self.popup then
    self.popup:unmount()
    self.popup = nil
  end
end

return Diagnostics.new()
