local M = {}

function M.concat_tables(...)
  local result = {}
  for _, t in ipairs({ ... }) do
    vim.list_extend(result, t)
  end
  return result
end

function M.parse_severity(severity)
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

---@param msg string
function M.clean_action_title(msg)
  local pattern = "%(.+%)%S$"
  if msg:find(pattern) then
    return msg:gsub(pattern, "")
  end
  return msg
end

---@param diagnostic Diagnostic
function M.diagnostic_source_str(diagnostic)
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

  return source_code_str
end

return M
