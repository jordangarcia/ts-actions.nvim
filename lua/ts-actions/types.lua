---@class GetActionConfigParams
---@field title string
---@field invalid_keys string[]
---@field override_function? fun(params: GetActionConfigParams): ActionConfig | nil
---@field priorities? ActionConfig[]
---@field valid_keys? string[]

---@class ActionConfig
---@field pattern string
---@field key string
---@field order? integer

---@class ActionOption
---@field action CodeAction
---@field client_id integer
---@field key string
---@field title string
---@field order integer

---@class WindowOpts
---@field title? string
---@field divider? string
---@field border? string | table
---@field window_hl? string
---@field x_offset? integer
---@field y_offset? integer
---@field dismiss_keys? string[]
---@field highlight table<string, string>
---@field relative? string
---@field hide_cursor? boolean

---@class SelectOpts
---@field prompt? string
---@field format_item? fun(item: any): string
---@field kind? string

---@class Config
---Specifies the priority and keys to map to patterns matching code actions.
---@field priority? table<string, ActionConfig[]>
---Specifies the priority and keys to map to patterns matching code actions.
---@field severity? table<string, number>
---Keys to use to map options.
---@field keys? string[] | string
---Keys to use to dismiss the popup.
---@field dismiss_keys? string[]
---Override function to map keys to actions.
---@field override_function? fun(params: GetActionConfigParams): ActionConfig | nil
---Override filter code actions
---@field filter_function? fun(action: CodeAction): boolean
--
---@class ParsedConfig : Config
---@field keys string[]

---@class CodeAction
---@field title string
---@field kind? string
---@field isPreferred? boolean
---@field diagnostics? Diagnostic[]
---@field edit? table
---@field command? table

---@class CodeActionResult
---@field client_id integer
---@field client_name string
---@field action CodeAction
