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

---@private
---@param bufnr integer
---@param mode "v"|"V"
---@return table {start={row, col}, end={row, col}} using (1, 0) indexing
function M.range_from_selection(bufnr, mode)
  -- TODO: Use `vim.region()` instead https://github.com/neovim/neovim/pull/13896
  -- [bufnum, lnum, col, off]; both row and column 1-indexed
  local start = vim.fn.getpos("v")
  local end_ = vim.fn.getpos(".")
  local start_row = start[2]
  local start_col = start[3]
  local end_row = end_[2]
  local end_col = end_[3]

  -- A user can start visual selection at the end and move backwards
  -- Normalize the range to start < end
  if start_row == end_row and end_col < start_col then
    end_col, start_col = start_col, end_col
  elseif end_row < start_row then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end
  if mode == "V" then
    start_col = 1
    local lines = vim.api.nvim_buf_get_lines(bufnr, end_row - 1, end_row, true)
    end_col = #lines[1]
  end
  return {
    ["start"] = { start_row, start_col - 1 },
    ["end"] = { end_row, end_col - 1 },
  }
end

---@generic T
---@param tbl T
---@param field? string
---@return T
function M.priority_sort(tbl, field)
  field = field or "order"
  local res = {}

  for i, v in ipairs(tbl) do
    local inserted = false
    local same = false
    for i2, v2 in ipairs(res) do
      if v[field] > v2[field] then
        -- replace
        table.insert(res, i2, v)
        inserted = true
        break
      elseif v2[field] == v[field] then
        same = true
        break
      elseif v[field] < v2[field] and same then
        table.insert(res, i2, v)
        inserted = true
      end
    end

    if not inserted then
      -- add to end
      table.insert(res, v)
    end
  end

  return res
end

return M
