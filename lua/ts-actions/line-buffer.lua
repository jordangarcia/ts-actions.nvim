local Line = require("nui.line")
local Text = require("nui.text")

---@class LineBuffer
---@field lines Line[]
---@field current_line Line|nil
---@field divider_indices table<number, {char: string, highlight: string|nil, index: integer}>
---@field max_width number
---@field padding number
local LineBuffer = {}
LineBuffer.__index = LineBuffer

---@class Line
---@class Text

---@param opts { max_width: number, padding: number }?
---@return LineBuffer
function LineBuffer:new(opts)
  opts =
    vim.tbl_deep_extend("force", { max_width = 80, padding = 0 }, opts or {})
  local self = setmetatable({}, LineBuffer)
  self.lines = {}
  self.current_line = nil
  self.divider_indices = {}
  self.max_width = opts.max_width
  self.padding = opts.padding
  self:newline()
  return self
end

---@return LineBuffer
function LineBuffer:newline()
  if self.current_line then
    table.insert(self.lines, self.current_line)
  end
  self.current_line = Line()
  return self
end

---@param text string
---@param highlight string|nil
function LineBuffer:break_line(text, highlight)
  if not self.current_line then
    error("Must call newline() before appending content")
  end

  local function append_line(line)
    self.current_line:append(Text(line, highlight))
    self:newline()
  end

  local remaining = text
  while #remaining > 0 do
    local line_width_available = self.max_width - self.current_line:width()
    if #remaining <= line_width_available then
      self.current_line:append(Text(remaining, highlight))
      break
    end

    local break_point = line_width_available

    -- Search backwards for a space, up to 20 characters
    for i = break_point, math.max(1, line_width_available - 10), -1 do
      if remaining:sub(i, i) == " " then
        break_point = i -- Break before the space
        break
      end
    end

    append_line(remaining:sub(1, break_point))
    remaining = remaining:sub(break_point + 1)
  end
end

---@param content string
---@param highlight string|nil
---@return LineBuffer
function LineBuffer:append(content, highlight)
  if not self.current_line then
    error("Must call newline() before appending content")
  end

  local parts =
    vim.split(tostring(content), "\n", { plain = false, trimempty = true })
  for i, part in ipairs(parts) do
    if i > 1 then
      self:newline()
    end
    self:break_line(part, highlight)
  end
  return self
end

---@param sep_char? string
---@param highlight? string
---@return LineBuffer
function LineBuffer:divider(sep_char, highlight)
  self:newline()
  table.insert(self.divider_indices, {
    index = #self.lines + 1,
    char = sep_char or "-",
    highlight = highlight or "Comment",
  })
  return self
end

---@param bufnr number
function LineBuffer:render(bufnr)
  if self.current_line then
    table.insert(self.lines, self.current_line)
    self.current_line = nil
  end

  local divider_width = self:width() - (2 * self.padding)

  -- Render lines
  for i, line in ipairs(self.lines) do
    if
      not vim.tbl_contains(
        vim.tbl_map(function(d)
          return d.index
        end, self.divider_indices),
        i
      )
    then
      -- This is not a divider line, apply padding
      local padded_line = Line()
      padded_line:append(Text(string.rep(" ", self.padding)))
      padded_line:append(line)
      padded_line:append(Text(string.rep(" ", self.padding)))
      padded_line:render(bufnr, -1, i)
    else
      local divider = vim.tbl_filter(function(d)
        return d.index == i
      end, self.divider_indices)[1]

      local padded_line = Line()
      padded_line:append(
        -- Text(string.rep(divider.char, self.padding), divider.highlight)
        Text(string.rep(" ", self.padding), divider.highlight)
      )
      padded_line:append(
        Text(string.rep(divider.char, divider_width), divider.highlight)
      )
      padded_line:append(
        -- Text(string.rep(divider.char, self.padding), divider.highlight)
        Text(string.rep(" ", self.padding), divider.highlight)
      )
      padded_line:render(bufnr, -1, i)
    end
  end
end

---@return number
function LineBuffer:width()
  local max_width = 0
  for i, line in ipairs(self.lines) do
    max_width = math.max(max_width, line:width())
  end
  if self.current_line then
    max_width = math.max(max_width, self.current_line:width())
  end
  return math.min(max_width, self.max_width) + (2 * self.padding)
end

---@return number
function LineBuffer:height()
  return #self.lines + (self.current_line and 1 or 0)
end

---@return string
function LineBuffer:debug()
  local result = {}
  local total_width = self:width()

  -- Add all completed lines
  for i, line in ipairs(self.lines) do
    if
      vim.tbl_contains(
        vim.tbl_map(function(d)
          return d.index
        end, self.divider_indices),
        i
      )
    then
      -- This is a divider line
      local divider = vim.tbl_filter(function(d)
        return d.index == i
      end, self.divider_indices)[1]
      result[i] = string.rep(divider.char, total_width)
    else
      -- This is a content line
      local content = line:content()
      result[i] = string.rep(" ", self.padding)
        .. content
        .. string.rep(" ", total_width - #content - self.padding)
    end
  end

  -- Add current line if it exists
  if self.current_line then
    local content = self.current_line:content()
    table.insert(
      result,
      string.rep(" ", self.padding)
        .. content
        .. string.rep(" ", total_width - #content - self.padding)
    )
  end

  -- Join all lines with newlines
  return table.concat(result, "\n")
end

return LineBuffer
