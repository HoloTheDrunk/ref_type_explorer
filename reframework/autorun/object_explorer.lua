---@type string
local type_paths = ""
---Index of the type currently being processed
---@type integer
local current_type = 1

---@type integer[]
local selected_method = {}
---@type string[]
local method_query = {}

---@type integer[]
local selected_field = {}
---@type string[]
local field_query = {}

---@type table<RETypeDefinition, REMethodDefinition[]>
local method_cache = {}
---@type table<RETypeDefinition, FilteredArray>
local method_name_cache = {}

---@type table<RETypeDefinition, REField[]>
local field_cache = {}
---@type table<RETypeDefinition, FilteredArray>
local field_name_cache = {}

local function init()
  type_paths = ""

  selected_method = {}
  method_query = {}

  selected_field = {}
  field_query = {}

  method_cache = {}
  method_name_cache = {}

  field_cache = {}
  field_name_cache = {}
end
init()

-----------------------------

---@class FilteredArray
---@field private filter string A Lua filter
---@field private data string[] The actual strings stored
---@field private _cache integer[] A cache of the indices of strings that match the filter
local FilteredArray = {}

---@param data string[]
---@param filter string A regex filter
---@return FilteredArray
function FilteredArray.new(data, filter)
  local res = {
    data = data,
    filter = filter,
    _cache = {}
  }
  setmetatable(res, FilteredArray)
  return res
end

---@param data string[]
---@return nil
function FilteredArray:set_data(data)
  self.data = data
  self._cache = {}
end

---@param filter string
---@return nil
function FilteredArray:set_filter(filter)
  if self.filter == filter then
    return
  end
  self.filter = filter
  self._cache = {}
end

---@return nil
function FilteredArray:run_filter()
  for i, str in ipairs(self.data) do
    if string.find(str, self.filter) ~= nil then
      self._cache[#self._cache + 1] = i
    end
  end
end

---@return integer
function FilteredArray:__len()
  if #self._cache == 0 then
    self:run_filter()
  end
  return #self._cache
end

---@param index integer
---@return integer
function FilteredArray:get_raw_index(index)
  if #self._cache == 0 then
    self:run_filter()
  end
  return self._cache[index]
end

---Logically speaking this method would be unnecessary, but the imgui.combo
---implementation doesn't want to play nice for some reason.
---@return string[]
function FilteredArray:get_filtered()
  local names = {}
  for i = 1, #self do
    names[#names + 1] = self.data[self._cache[i]]
  end
  return names
end

---@param key unknown
---@return string
function FilteredArray:__index(key)
  if type(key) ~= 'number' then
    return FilteredArray[key]
  end

  if #self._cache == 0 then
    self:run_filter()
  end
  return self.data[self._cache[key]]
end

---@param index unknown
---@param value string
function FilteredArray:__newindex(index, value)
  self.data[index] = value
  self._cache = {}
end

-----------------------------

---@param type RETypeDefinition
local function cache_methods(type)
  if method_cache[type] == nil then
    method_cache[type] = type:get_methods()
    local names = {}
    for _, method in ipairs(method_cache[type]) do
      names[#names + 1] = method:get_name()
    end
    method_name_cache[type] = FilteredArray.new(names, method_query[current_type])
  end
  return method_cache[type]
end

---@param type RETypeDefinition
local function cache_fields(type)
  if not field_cache[type] then
    field_cache[type] = type:get_fields()
    local names = {}
    for _, field in ipairs(field_cache[type]) do
      names[#names + 1] = field:get_name()
    end
    field_name_cache[type] = FilteredArray.new(names, field_query[current_type])
  end
  return field_cache[type]
end

---@param type RETypeDefinition
---@return nil
local function draw_inheritance(type)
  local parent = type:get_parent_type()
  while parent ~= nil do
    imgui.text(string.format("-> %s", parent:get_full_name()))
    parent = parent:get_parent_type()
  end
end

---@param type RETypeDefinition
---@return nil
local function draw_methods(type)
  local methods = cache_methods(type)
  if #methods > 0 then
    local cache = method_name_cache[type]

    _, method_query[current_type] = imgui.input_text("Method Filter", method_query[current_type])
    cache:set_filter(method_query[current_type])

    if #cache > 0 then
      _, selected_method[current_type] = imgui.combo("Method", math.min(selected_method[current_type] or 1, #cache),
        cache:get_filtered())
    else
      _, _ = imgui.combo("Method", 1, { "no matches" })
      return
    end

    local method = methods[cache:get_raw_index(selected_method[current_type] or 1)]

    if method:is_static() then
      imgui.text_colored("STATIC", 0xff7777ff)
    end

    local decl = method:get_declaring_type()
    if decl and decl ~= type then
      imgui.text(string.format("Declaring type: %s", decl:get_full_name()))
    end

    local param_names = method:get_param_names()
    local param_types = method:get_param_types()
    for i = 1, method:get_num_params() do
      imgui.text_colored(string.format("@param %s: %s", param_names[i], param_types[i]:get_full_name()), 0xffec9238)
    end

    local return_type = method:get_return_type()
    if return_type then
      imgui.text_colored(string.format("@return %s", return_type:get_full_name()), 0xff54a4e6)
    end
  end
end

---@param type RETypeDefinition
---@return nil
local function draw_fields(type)
  local fields = cache_fields(type)
  if #fields > 0 then
    local cache = field_name_cache[type]

    _, field_query[current_type] = imgui.input_text("Field Filter", field_query[current_type])
    cache:set_filter(field_query[current_type])

    if #cache > 0 then
      _, selected_field[current_type] = imgui.combo("Field", math.min(selected_field[current_type] or 1, #cache),
        cache:get_filtered())
    else
      _, _ = imgui.combo("Field", 1, { "no matches" })
      return
    end

    local field = fields[cache:get_raw_index(selected_field[current_type] or 1)]

    if field:is_static() then
      imgui.text_colored("STATIC", 0xff7777ff)
    end

    local decl = field:get_declaring_type()
    if decl and decl ~= type then
      imgui.text(string.format("Declaring type: %s", decl:get_full_name()))
    end

    local field_type = field:get_type()
    local field_type_name = field_type and field_type:get_full_name() or "unknown"
    imgui.text(string.format("Type: %s", field_type_name))
  end
end

local function draw_ui()
  _, type_paths = imgui.input_text("Type paths (separated by commas ',')", type_paths)

  current_type = 1
  for ty in string.gmatch(type_paths, "([^,]+)") do
    ty = string.gsub(ty, "%s+", "")
    local type = sdk.find_type_definition(ty)
    if type ~= nil then
      selected_method[current_type] = selected_method[current_type] or 1
      method_query[current_type] = method_query[current_type] or ""
      selected_field[current_type] = selected_field[current_type] or 1
      field_query[current_type] = field_query[current_type] or ""

      if imgui.tree_node(ty) then
        draw_inheritance(type)
        draw_methods(type)
        draw_fields(type)
        imgui.tree_pop()
      end
    else
      imgui.text_colored(string.format("%s not found", ty), 0xff7777ff)
    end
    current_type = current_type + 1
  end
end

local function main()
  re.on_draw_ui(function()
    if not imgui.tree_node("Object Explorer") then return end
    if imgui.button("Reset") then init() end
    if not pcall(draw_ui) then
      imgui.text("Failed to render menu")
      log.error("[object_explorer] Failed to render menu")
    end
    imgui.tree_pop()
  end)
end

main()
