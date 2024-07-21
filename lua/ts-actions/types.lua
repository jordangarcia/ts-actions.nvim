---@class GetActionConfigParams
---@field title string
---@field invalid_keys string[]
---@field override_function? fun(params: GetActionConfigParams): ActionConfig | nil
---@field priorities? ActionConfig[]
---@field valid_keys? string[] | string

---@class ActionConfig
---@field pattern string
---@field key string
---@field order? integer

---@class ActionOption
---@field action CodeAction
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
---Configures options for the code action and select popups.
---@field popup? PopupConfig
---Specifies the priority and keys to map to patterns matching code actions.
---@field priority? table<string, ActionConfig[]>
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

---@class PopupConfig
---Title of the popup.
---@field title? string
---Specifies what the popup is relative to.
---@field relative? string
---Style of the popup border. Can be "single", "double", "rounded", "thick", or
---a table of strings in the format
---{"top left", "top", "top right", "right", "bottom right", "bottom", "bottom left", "left"}.
---@field border? string | string[]
---Whether to hide the cursor when the popup is shown.
---@field hide_cursor? boolean
---Configures the highlights of different aspects of the popup.
---@field highlight? table<string, string>
