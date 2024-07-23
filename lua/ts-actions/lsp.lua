---@alias DiagnosticSeverity
---| 1 # Error
---| 2 # Warning
---| 3 # Information
---| 4 # Hint

---@class GetNextOpts
---@field severity? DiagnosticSeverity
---@field check_cursor? boolean

---@class GotoDiagnosticOpts
---@field severity? DiagnosticSeverity

local M = {}

local textDocument_codeAction = "textDocument/codeAction"
local codeAction_resolve = "codeAction/resolve"

---get the line or cursor diagnostics
---@param opt table
---@return Diagnostic[]
local function get_diagnostic(opt)
  local cur_buf = vim.api.nvim_get_current_buf()
  if opt.buffer then
    return vim.diagnostic.get(cur_buf)
  end
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  local entrys = vim.diagnostic.get(cur_buf, { lnum = line - 1 })
  if opt.line then
    return entrys
  end
  if opt.cursor then
    local res = {}
    for _, v in pairs(entrys) do
      if v.col <= col and (v.end_col and v.end_col > col or true) then
        res[#res + 1] = v
      end
    end
    return res
  end
  return vim.diagnostic.get()
end

---@param opts? GetNextOpts
---@return Diagnostic|nil
function M.get_next(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR
  local check_cursor = opts.check_cursor or false

  if check_cursor then
    local cursor_diagnostics = get_diagnostic({ cursor = true })
    if #cursor_diagnostics > 0 then
      -- Find the diagnostic with the highest severity (lowest severity number)
      local highest_severity_diag = cursor_diagnostics[1]
      for _, diag in ipairs(cursor_diagnostics) do
        if diag.severity < highest_severity_diag.severity then
          highest_severity_diag = diag
        end
      end
      return highest_severity_diag
    end
  end

  return vim.diagnostic.get_next({
    severity = { min = severity },
    wrap = true,
    float = false,
  })
end

function M.support_resolve(client, bufnr)
  if vim.version().minor >= 10 then
    local reg = client.dynamic_capabilities:get(
      "textDocument/codeAction",
      { bufnr = bufnr }
    )
    return vim.tbl_get(reg or {}, "registerOptions", "resolveProvider")
      or client.supports_method("codeAction/resolve")
  end
  return vim.tbl_get(
    client.server_capabilities,
    "codeActionProvider",
    "resolveProvider"
  )
end

function M.get_resolve_action(client, action, bufnr)
  if not M.support_resolve(client) then
    return
  end
  return client.request_sync("codeAction/resolve", action, 1500, bufnr).result
end

---@param opts? GotoDiagnosticOpts
function M.goto_next(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR

  local next_diagnostic =
    M.get_next({ severity = severity, check_cursor = true })

  if next_diagnostic then
    vim.api.nvim_win_set_cursor(
      0,
      { next_diagnostic.lnum + 1, next_diagnostic.col }
    )
  end
end

---@param CodeAction[] | nil
---@return CodeAction[] | nil
local function request_code_action(params)
  local buffer = vim.api.nvim_get_current_buf()
  ---@type table<integer, {result: CodeAction[], error: table? }>?, string?
  local results_lsp, err = vim.lsp.buf_is_attached

  vim.lsp.buf_request_sync(buffer, "textDocument/codeAction", params, 10000)
  if err then
    return vim.notify("ERROR: " .. err, vim.log.levels.ERROR)
  end
  if not results_lsp or vim.tbl_isempty(results_lsp) then
    return vim.notify(
      "No results from textDocument/codeAction",
      vim.log.levels.INFO
    )
  end
  local commands = {}
  for client_id, response in pairs(results_lsp) do
    if response.result then
      local client = vim.lsp.get_client_by_id(client_id)
      for _, result in pairs(response.result) do
        ---@type CodeAction
        local res = result
        res.client_id = client_id
        res.client_name = client and client.name or ""
        res.buffer = buffer
        table.insert(commands, result)
      end
    end
  end
  return commands
end

function M.code_action()
  M.bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local context = {
    diagnostics = vim.lsp.diagnostic.get_line_diagnostics(
      M.bufnr,
      lnum,
      {},
      nil
    ),
  }
  local params = vim.lsp.util.make_range_params()
  params.context = context
  return request_code_action(params)
end

-- TODO(jordan) figure out how to use this
function M.range_code_action()
  M.bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local context = {
    diagnostics = vim.lsp.diagnostic.get_line_diagnostics(
      M.bufnr,
      lnum,
      {},
      nil
    ),
  }
  local params = vim.lsp.util.make_given_range_params()
  params.context = context
  return request_code_action(params)
end

-- ---@param action table
-- ---@param client vim.lsp.Client
-- ---@param ctx { bufnr: integer }
-- local function apply_action(action, client, ctx)
--   if action.edit then
--     vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
--   end
--   local a_cmd = action.command
--   if a_cmd then
--     local command = type(a_cmd) == "table" and a_cmd or action --[[@as table]]
--     client:_exec_cmd(command, ctx)
--   end
-- end

---@param ctx { bufnr: integer }
local function apply_action(action, client, ctx)
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
  end
  if action.command then
    local command = type(action.command) == "table" and action.command or action
    local func = client.commands[command.command]
      or vim.lsp.commands[command.command]
    if func then
      ctx.client_id = client.id
      func(command, ctx)
    else
      local params = {
        command = command.command,
        arguments = command.arguments,
        workDoneToken = command.workDoneToken,
      }
      client.request("workspace/executeCommand", params, nil, ctx.bufnr)
    end
  end
end

---@param action CodeAction
function M.execute_command(action)
  local client = assert(vim.lsp.get_client_by_id(action.client_id))

  local ctx = { bufnr = action.buffer }
  ---@type table?
  local reg
  ---@type boolean
  local supports_resolve
  if action.data then
    supports_resolve = M.support_resolve(client, action.buffer)
  end
  if not action.edit and client and supports_resolve then
    client.request(codeAction_resolve, action, function(err, resolved_action)
      if err then
        if action.command then
          apply_action(action, client, ctx)
        else
          vim.notify(err.code .. ": " .. err.message, vim.log.levels.ERROR)
        end
      else
        apply_action(resolved_action, client, ctx)
      end
    end, action.buffer)
  else
    apply_action(action, client, ctx)
  end
end

return M
