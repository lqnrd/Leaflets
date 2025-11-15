--[[
Leaflets are small and simple scripts to change and enhance your UI, easily shared with other players

TODO:
- COM
  - make functions private
  - prevent spam, verify sender before sending them a leaflet
  - show up/down while transferring
- GUI (https://www.wowace.com/projects/ace3/pages/ace-gui-3-0-widgets)
  - maybe switch to general tab when adding a new leaflet
  - blacklist chars when renaming a leaflet
  - make sure names are unique
]]

Leaflets = LibStub("AceAddon-3.0"):NewAddon("Leaflets", "AceComm-3.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
local AceGUI = LibStub("AceGUI-3.0")
local COM_CHANNEL = "L34f5"
-- version of new leaflets
local LEAFLET_VERSION_TAG = 1
-- minimum version of imported leaflets to be compatible
local LEAFLET_VERSION_COMPAT_TAG = 1
local SHARE_STRING_VERSION_TAG = 1

local DefaultO, O = {
  leaflets = {},
}

local mainFrame, selectedId
local selectedTab = "general"
local selectedEventGroupIndex
local leafletsSorted = {}
local leafletsButtons = {}
local leafletFrames = {}
local leafletsLinkedLast5Minutes, leafletsRequested = {}, {}
local myRealm = GetRealmName("player"):gsub("%s","")

--------------------------------------------------------------------------------
-- adding/loading leaflets
--------------------------------------------------------------------------------

local function cleanupLeafletsLinkedLast5Minutes()
  for leafletId, timestamp in pairs(leafletsLinkedLast5Minutes) do
    if timestamp < time() - 5*60 then
      leafletsLinkedLast5Minutes[leafletId] = nil
    end
  end
end
local function addRequestedLeaflet(playerName, leafletName)
  leafletsRequested[playerName] = leafletsRequested[playerName] or {}
  leafletsRequested[playerName][leafletName] = true
end
local function hasRequestedLeaflet(playerName, leafletName)
  return leafletsRequested[playerName] and leafletsRequested[playerName][leafletName]
end

-- WoW-safe pseudo UUID v4 generator
local function GenerateUUID()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  local function randomHexDigit(c)
  local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end
  local uuid = string.gsub(template, "[xy]", randomHexDigit)
  return uuid
end
function mysplit(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

local leafletsFunctionsCache = {}
local eventGroupFrameBin = {}
local function getNewEventFrame()
  if #eventGroupFrameBin > 0 then
    return table.remove(eventGroupFrameBin)
  end
  local f = CreateFrame("Frame")
  return f
end
local function removeEventFrame(f)
  f:UnregisterAllEvents()
  table.insert(eventGroupFrameBin, f)
end
local nextLeafletFramesCounter = 1
local function addLeafletBaseFrame(leaflet)
  if not leafletFrames[leaflet.id] then
    local f = CreateFrame("Frame", "LeafletFrame_"..nextLeafletFramesCounter, UIParent, "BackdropTemplate")
    f:SetPoint("CENTER")
    f:SetSize(100, 100)
    nextLeafletFramesCounter = nextLeafletFramesCounter + 1
    leafletFrames[leaflet.id] = f

    f.texts = {
      f:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
    }
    f.texts[1]:SetPoint("CENTER")
    f.texts[1]:SetText("")
    f.texts[1]:SetTextColor(1, 1, 1, 1)
    f.SetText = function(self, ...)
      f.texts[1]:SetText(...)
    end
    f.addNewText = function(self)
      local i = #f.texts + 1
      f.texts[i] = f:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
      f.texts[i]:SetPoint("CENTER")
      f.texts[i]:SetText("")
      f.texts[i]:SetTextColor(1, 1, 1, 1)
    end

    f:Hide()
  end
end
local function removeLeafletBaseFrame(leaflet)
  if leafletFrames[leaflet.id] then
    leafletFrames[leaflet.id]:UnregisterAllEvents()
    leafletFrames[leaflet.id]:Hide()
    -- no need to bin this one; how often do we remove leaflets in one session anyway?
    leafletFrames[leaflet.id] = nil
  end
end
local function sortLeaflets()
  leafletsSorted = {}
  for _, leaflet in pairs(O.leaflets) do
    table.insert(leafletsSorted, leaflet)
  end
  --table.sort(leafletsSorted, function(a, b) return a.name < b.name end)
  table.sort(leafletsSorted, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
end
local function findLeafletById(id)
  return O.leaflets[id]
end
local function findLeafletByName(name)
  for k, l in pairs(O.leaflets) do
    if l.name == name then
      return l
    end
  end
end
local function getUniqueLeafletName(name)
  local existingNames = {}
  for k, l in pairs(O.leaflets) do
    existingNames[l.name] = true
  end
  if not existingNames[name] then
    return name
  end
  local prefix, counter = name:match("^(.+)%s+(%d+)$")
  prefix = prefix or name
  counter = tonumber(counter) or 1
  repeat
    counter = counter + 1
    newName = prefix.." "..counter
  until not existingNames[newName]
  return newName
end
local function addLeaflet()
  local name = getUniqueLeafletName("Sample Leaflet")
  local newLeaflet = { -- single Leaflet
    v = LEAFLET_VERSION_TAG, -- [number]
    id = GenerateUUID(), -- [uuid string]
    name = name, -- [string]
    code = {
      init = "print(\"Sample Leaflet: code.init(\", leaflet:IsShown(), ...)", -- [string]
      --[[
      eventgroups = {
        {
          events = "PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED",
          func = "function(...)\n  print(...)\nend",
        },
      },
      ]]
    },
    --disabled = true, -- [boolean?] when truthy, this Leaflet's code will no longer be run
  }
  O.leaflets[newLeaflet.id] = newLeaflet
  addLeafletBaseFrame(newLeaflet)
  sortLeaflets()
  if mainFrame then
    mainFrame.refreshItemList()
    mainFrame.refreshItemDetailTabs(newLeaflet)
  end
end
local function verifyDefaultLeafletFields(data)
  if type(data) ~= "table" then return false end
  if type(data.v) ~= "number" then return false end
  if type(data.id) ~= "string" then return false end
  if type(data.name) ~= "string" then return false end
  local code = data.code
  if code then
    if type(code) ~= "table" then return false end
    if code.init and type(code.init) ~= "string" then return false end
    local eventgroups = code.eventgroups
    if eventgroups then
      if type(eventgroups) ~= "table" then return false end
      for k, v in pairs(eventgroups) do
        if type(k) ~= "number" then return false end
        if type(v) ~= "table" then return false end
        if type(v.events) ~= "string" then return false end
        if type(v.func) ~= "string" then return false end
      end
    end
  end
  return true
end
local function getLeafletFunctionsCache(leafletId)
  if not leafletsFunctionsCache[leafletId] then
    leafletsFunctionsCache[leafletId] = {
      env = {
        Vector2DMixin = Vector2DMixin
      },
      funcs = {},
      eventGroupFrameFuncs = {
        -- { frame = <frame>, func = <function> }
      },
    }
    -- set _G fallback for standard functions like print, math, etc.
    setmetatable(leafletsFunctionsCache[leafletId].env, {
      __index = function(t, k)
        if k == "leaflet" then
          return leafletFrames[leafletId]
        else
          return _G[k]
        end
      end
    })
  end
  return leafletsFunctionsCache[leafletId]
end
local function deleteLeaflet(leaflet)
  for k, l in pairs(O.leaflets) do
    if l.id == leaflet.id then
      local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
      for _, v in ipairs(leafletFunctionsCache.eventGroupFrameFuncs or {}) do
        removeEventFrame(v.frame)
      end
      O.leaflets[k] = nil
      removeLeafletBaseFrame(leaflet)
      break
    end
  end
  sortLeaflets()
  if mainFrame then
    mainFrame.refreshItemList()
    mainFrame.refreshItemDetailTabs()
  end
end
local function deleteLeafletEventGroup(leaflet, eventGroupIndex)
  if not leaflet or not eventGroupIndex then
    return
  end
  if leaflet.code and leaflet.code.eventgroups and leaflet.code.eventgroups[eventGroupIndex] then
    local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
    removeEventFrame(leafletFunctionsCache.eventGroupFrameFuncs[eventGroupIndex].frame)
    table.remove(leaflet.code.eventgroups, eventGroupIndex)
    table.remove(leafletFunctionsCache.eventGroupFrameFuncs, eventGroupIndex)
    selectedEventGroupIndex = nil
  end
end
local function addBlockToLeafletFunctionsCache(leaflet, funcString)
  local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
  local f, err = loadstring(funcString)
  if not f then
    print("|cffff0000[Leaflets] Error loading function of leaflet \""..(leaflet.name or "unnamed").."\":|r", err)
    return
  end
  -- set the environment for the function to the leaflet's environment
  setfenv(f, leafletFunctionsCache.env)
  table.insert(leafletFunctionsCache.funcs, f)
  return f
end
local function addFunctionToLeafletFunctionsCache(leaflet, funcString)
  local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
  local f, err = loadstring("return "..funcString)
  if not f then
    print("|cffff0000[Leaflets] Error loading function of leaflet \""..(leaflet.name or "unnamed").."\":|r", err)
    return
  end
  -- set the environment for the function to the leaflet's environment
  setfenv(f, leafletFunctionsCache.env)
  f = f()
  table.insert(leafletFunctionsCache.funcs, f)
  return f
end
local function addLeafletEventGroup(leaflet)
  -- add to leaflet
  leaflet.code = leaflet.code or {}
  leaflet.code.eventgroups = leaflet.code.eventgroups or {}
  local newEventGroup = {
    events = "PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED",
    func = "function(self, event, ...)\n  print(event, ...)\nend",
  }
  table.insert(leaflet.code.eventgroups, newEventGroup)
  local index = #(leaflet.code.eventgroups)

  -- add to cache
  local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
  local frame = getNewEventFrame()
  local func = addFunctionToLeafletFunctionsCache(leaflet, newEventGroup.func)
  frame:SetScript("OnEvent", func)
  local events = mysplit(newEventGroup.events or "", ",")
  for _, event in pairs(events) do
    frame:RegisterEvent(event)
  end
  table.insert(leafletFunctionsCache.eventGroupFrameFuncs, index, {frame = frame, func = func})

  return index
end
local function addEventGroupFramesToLeafletFunctionsCache(leaflet)
  local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
  if not leaflet.code or not leaflet.code.eventgroups then
    return
  end
  for i, g in ipairs(leaflet.code.eventgroups) do
    local frame = getNewEventFrame()
    local func = addFunctionToLeafletFunctionsCache(leaflet, g.func)
    frame:SetScript("OnEvent", func)
    local events = mysplit(g.events or "", ",")
    for _, event in pairs(events) do
      frame:RegisterEvent(event)
    end
    table.insert(leafletFunctionsCache.eventGroupFrameFuncs, i, {frame = frame, func = func})
  end
end
local function reloadEventGroupFrameEvents(leaflet, eventGroupIndex)
  local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
  if not leaflet.code or not leaflet.code.eventgroups then
    return
  end
  local g = leaflet.code.eventgroups[eventGroupIndex]
  if not g then
    return
  end
  local frame = leafletFunctionsCache.eventGroupFrameFuncs[eventGroupIndex].frame
  if not frame then
    return
  end
  frame:UnregisterAllEvents()
  local events = mysplit(g.events or "", ",")
  for _, event in pairs(events) do
    frame:RegisterEvent(event)
  end
end
local function reloadEventGroupFrameFunc(leaflet, eventGroupIndex)
  local leafletFunctionsCache = getLeafletFunctionsCache(leaflet.id)
  if not leaflet.code or not leaflet.code.eventgroups then
    return
  end
  local g = leaflet.code.eventgroups[eventGroupIndex]
  if not g then
    return
  end
  local frame = leafletFunctionsCache.eventGroupFrameFuncs[eventGroupIndex].frame
  if not frame then
    return
  end
  local func = addFunctionToLeafletFunctionsCache(leaflet, g.func)
  frame:SetScript("OnEvent", func)
  leafletFunctionsCache.eventGroupFrameFuncs[eventGroupIndex].func = func
end
local function loadAndExecuteLeafletBlock(leaflet, funcString, funcName, ...)
  local f = addBlockToLeafletFunctionsCache(leaflet, funcString)
  if f then
    local ok, err = pcall(f, funcName, ...)
    if not ok then
      print("|cffff0000[Leaflets] Error in function \""..funcName.."\" of leaflet \""..(leaflet.name or "unnamed").."\":|r", err)
    end
  end
end
local function loadAndExecuteLeafletCodes(leaflet)
  if leaflet.disabled then
    return
  end
  addLeafletBaseFrame(leaflet)
  if leaflet.code and leaflet.code.init then
    loadAndExecuteLeafletBlock(leaflet, leaflet.code.init, "init")
  end
  local ok, err = pcall(addEventGroupFramesToLeafletFunctionsCache, leaflet)
  if not ok then
    print("|cffff0000[Leaflets] Error in event group of leaflet \""..(leaflet.name or "unnamed").."\":|r", err)
  end
end
local function unloadLeafletCodes(leaflet)
  if not leaflet.disabled then
    return
  end
  local leafletFunctionsCache = leafletsFunctionsCache[leaflet.id]
  if not leafletFunctionsCache then
    return
  end
  -- events
  for _, event in ipairs(leafletFunctionsCache.eventGroupFrameFuncs) do
    removeEventFrame(event.frame)
  end
  removeLeafletBaseFrame(leaflet)
  -- clear leaflet cache
  leafletsFunctionsCache[leaflet.id] = nil
end
local function loadLeaflets()
  for _, leaflet in pairs(O.leaflets) do
    addLeafletBaseFrame(leaflet)
    if not leaflet.disabled then
      loadAndExecuteLeafletCodes(leaflet)
    end
  end
  sortLeaflets()
end

local function importLeaflet(leaflet, bOverwrite)
  local found = false
  for k, l in pairs(O.leaflets) do
    if l.id == leaflet.id then
      if bOverwrite then
        if leaflet.name ~= l.name then
          leaflet.name = getUniqueLeafletName(leaflet.name)
        end
        O.leaflets[k] = leaflet
        sortLeaflets()
        print("leaflet "..leaflet.name.." overwritten")
      else
        -- create copy
        leaflet.id = GenerateUUID()
        leaflet.name = getUniqueLeafletName(leaflet.name)
        O.leaflets[leaflet.id] = leaflet
        addLeafletBaseFrame(leaflet)
        sortLeaflets()
        print("leaflet "..leaflet.name.." imported")
      end
      found = true
      break
    end
  end
  if not found then
    leaflet.name = getUniqueLeafletName(leaflet.name)
    O.leaflets[leaflet.id] = leaflet
    addLeafletBaseFrame(leaflet)
    sortLeaflets()
    print("new leaflet "..leaflet.name.." imported")
  end
  if mainFrame then
    mainFrame.refreshItemList()
    mainFrame.refreshItemDetailTabs(leaflet)
  end
  loadAndExecuteLeafletCodes(leaflet)
end

--------------------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------------------

function Leaflets:OpenConfig()
  if mainFrame then
    if mainFrame:IsShown() then
      mainFrame:Hide()
    else
      mainFrame:Show()
    end
    return
  end

  -- root window
  mainFrame = AceGUI:Create("Frame")
  mainFrame:SetTitle("Leaflets Configuration")
  mainFrame:SetStatusText("|cffaaaaffLeaflets |r"..(O.addonVersion or ""))
  mainFrame:SetCallback("OnClose", function(widget)
    mainFrame:Hide()
  end)
  mainFrame:SetLayout("Flow")
  mainFrame:SetWidth(600)
  mainFrame:SetHeight(400)
  _G["LeafletsMainFrame"] = mainFrame.frame
  table.insert(UISpecialFrames, "LeafletsMainFrame")

  ------------------------------------------------
  -- Left: Item list
  ------------------------------------------------
  local itemList = AceGUI:Create("ScrollFrame")
  itemList:SetLayout("List")
  itemList:SetFullHeight(true)
  itemList:SetWidth(200)
  mainFrame:AddChild(itemList)

  ------------------------------------------------
  -- Right: Editor panel
  ------------------------------------------------
  local rightPanelContainerFrame = CreateFrame("Frame", "LEAF_rightPanelContainer", mainFrame.content)
  rightPanelContainerFrame:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 200, 0)
  rightPanelContainerFrame:SetPoint("BOTTOMRIGHT", mainFrame.content, "BOTTOMRIGHT")
  mainFrame.rightPanelContainerFrame = rightPanelContainerFrame
  local rightPanelACEGroup = AceGUI:Create("SimpleGroup")
  rightPanelACEGroup:SetFullWidth(true)
  rightPanelACEGroup:SetFullHeight(true)
  rightPanelACEGroup:SetLayout("Fill")
  rightPanelACEGroup.frame:SetParent(rightPanelContainerFrame)
  rightPanelACEGroup.frame:SetAllPoints()
  rightPanelACEGroup.frame:Show()
  mainFrame.rightPanelACEGroup = rightPanelACEGroup

  ------------------------------------------------
  -- Helpers
  ------------------------------------------------
  local function refreshItemList()
    itemList:ReleaseChildren()

    -- add new / import leaflet
    local topGroup = AceGUI:Create("SimpleGroup")
    topGroup:SetLayout("Flow")
    itemList:AddChild(topGroup)
    local btnNew = AceGUI:Create("Button")
    btnNew:SetText("New Leaflet")
    btnNew:SetWidth(120)
    btnNew:SetCallback("OnClick", function()
      addLeaflet()
    end)
    topGroup:AddChild(btnNew)
    local btnImport = AceGUI:Create("Button")
    btnImport:SetText("Import")
    btnImport:SetWidth(80)
    btnImport:SetCallback("OnClick", function()
      mainFrame.refreshItemDetailTabs()
    end)
    topGroup:AddChild(btnImport)

    -- existing leaflets
    leafletsButtons = {}
    for _, item in ipairs(leafletsSorted) do
      btn = AceGUI:Create("LeafletsListButton")
      btn:SetText(item.name)
      btn:SetFullWidth(true)
      btn:SetCallback("OnClick", function()
        if IsShiftKeyDown() then
          local linkData = string.format("Leaflets:%s", item.name)
          local chatLink = string.format("[%s]", linkData)
          ChatEdit_InsertLink(chatLink) -- => COM
          cleanupLeafletsLinkedLast5Minutes()
          leafletsLinkedLast5Minutes[item.id] = time()
        else
          mainFrame.refreshItemDetailTabs(item)
        end
      end)
      itemList:AddChild(btn)
      leafletsButtons[item.id] = btn
    end
  end
  mainFrame.refreshItemList = refreshItemList

  local function refreshItemDetailTab(container, leaflet, tabId)
    container:ReleaseChildren()
    selectedTab = tabId

    local editGroup = AceGUI:Create("ScrollFrame")
    editGroup:SetFullWidth(true)
    editGroup:SetFullHeight(true)
    editGroup:SetLayout("List")
    container:AddChild(editGroup)

    if tabId == "leaf" then
      local disabledCheckbox = AceGUI:Create("CheckBox")
      disabledCheckbox:SetLabel("never load")
      disabledCheckbox:SetFullWidth(true)
      disabledCheckbox:SetValue(leaflet.disabled and true or false)
      editGroup:AddChild(disabledCheckbox)
      disabledCheckbox:SetCallback("OnValueChanged", function(self, event, value)
        if not selectedId then
          print("No item selected.")
          return
        end
        local leaflet = O.leaflets[selectedId]
        if value then
          leaflet.disabled = true
          unloadLeafletCodes(leaflet)
        else
          leaflet.disabled = nil
          loadAndExecuteLeafletCodes(leaflet)
        end
        --refreshItemList()
      end)

      local nameEditBox = AceGUI:Create("EditBox")
      nameEditBox:SetLabel("Name")
      nameEditBox:SetFullWidth(true)
      nameEditBox:SetText(leaflet.name or "")
      editGroup:AddChild(nameEditBox)
      nameEditBox:SetCallback("OnEnterPressed", function(self, event, value)
        if not selectedId then
          print("No item selected.")
          return
        end
        local item = O.leaflets[selectedId]
        item.name = value or ""
        sortLeaflets()
        self:ClearFocus()
        refreshItemList()
        if leafletsButtons[selectedId] then
          leafletsButtons[selectedId].frame:LockHighlight()
        end
      end)

      local exportButton = AceGUI:Create("Button")
      exportButton:SetText("Export to string")
      editGroup:AddChild(exportButton)
      local exportEditBox = AceGUI:Create("MultiLineEditBox")
      exportEditBox:SetLabel("copy")
      exportEditBox:SetFullWidth(true)
      exportEditBox:SetNumLines(6)
      exportEditBox:SetText("")
      exportEditBox:SetDisabled(true)
      editGroup:AddChild(exportEditBox)
      exportButton:SetCallback("OnClick", function()
        if not selectedId then
          return
        end
        local leaflet = O.leaflets[selectedId]
        exportEditBox:SetText(Leaflets:LeafletToString(leaflet))
        exportEditBox:SetDisabled(false)
      end)

      local deleteButton = AceGUI:Create("Button")
      deleteButton:SetText("Delete Leaflet")
      editGroup:AddChild(deleteButton)
      deleteButton:SetCallback("OnClick", function()
        if not selectedId then
          print("No item selected.")
          return
        end
        local item = O.leaflets[selectedId]
        StaticPopupDialogs["LEAFLET_DELETE"] = {
          text = "Delete leaflet \""..item.name.."\"?",
          button1 = "Yes",
          button2 = "No",
          OnAccept = function()
            deleteLeaflet(item)
          end,
          timeout = 0,
          whileDead = true,
          hideOnEscape = true,
        }
        StaticPopup_Show("LEAFLET_DELETE")
      end)
    elseif tabId == "general" then
      local descEditBox = AceGUI:Create("MultiLineEditBox")
      descEditBox:SetLabel("init code")
      descEditBox:SetFullWidth(true)
      descEditBox:SetNumLines(6)
      descEditBox:SetText(leaflet.code and leaflet.code.init or "")
      editGroup:AddChild(descEditBox)
      descEditBox:SetCallback("OnEnterPressed", function(self, event, value)
        if not selectedId then
          print("No item selected.")
          return
        end
        local leaflet = O.leaflets[selectedId]
        if leaflet.code then
          leaflet.code.init = value or ""
          if strlen(leaflet.code.init) > 0 then
            loadAndExecuteLeafletBlock(leaflet, leaflet.code.init, "init", "OPTIONS")
          end
        end
        self:ClearFocus()
        --refreshItemList()
      end)
    elseif tabId == "events" then
      local dd = AceGUI:Create("DropdownGroup")
      dd:SetFullWidth(true)
      dd:SetFullHeight(true)
      dd:SetLayout("List")
      dd:SetTitle("Event group")
      local groupList = {}
      if leaflet.code and leaflet.code.eventgroups then
        for i, group in ipairs(leaflet.code.eventgroups) do
          table.insert(groupList, i, group.events or "[no events]")
        end
      end
      table.insert(groupList, "+ add group")
      dd:SetGroupList(groupList)
      editGroup:AddChild(dd)
      dd:SetCallback("OnGroupSelected", function(self, event, key)
        dd:ReleaseChildren()
        if key > (leaflet.code and leaflet.code.eventgroups and #(leaflet.code.eventgroups) or 0) then
          local newEventGroupIndex = addLeafletEventGroup(leaflet)
          selectedEventGroupIndex = newEventGroupIndex
          refreshItemDetailTab(container, leaflet, tabId)
          print("new event group added")
          return
        elseif key <= 0 then
          selectedEventGroupIndex = nil
          return
        end
        selectedEventGroupIndex = key

        local eventGroup = leaflet.code.eventgroups[key]

        -- events
        local eventsEditBox = AceGUI:Create("EditBox")
        eventsEditBox:SetLabel("events (comma separated)")
        eventsEditBox:SetFullWidth(true)
        eventsEditBox:SetText(eventGroup.events or "")
        dd:AddChild(eventsEditBox)
        eventsEditBox:SetCallback("OnEnterPressed", function(self, event, value)
          if not eventGroup then
            return
          end
          eventGroup.events = value or ""
          self:ClearFocus()
          refreshItemDetailTab(container, leaflet, tabId)
          reloadEventGroupFrameEvents(leaflet, selectedEventGroupIndex)
          --TODO: call func with OPTIONS event
        end)

        -- func
        local eventsFuncEditBox = AceGUI:Create("MultiLineEditBox")
        eventsFuncEditBox:SetLabel("code")
        eventsFuncEditBox:SetFullWidth(true)
        eventsFuncEditBox:SetNumLines(6)
        eventsFuncEditBox:SetText(eventGroup.func or "")
        dd:AddChild(eventsFuncEditBox)
        eventsFuncEditBox:SetCallback("OnEnterPressed", function(self, event, value)
          if not eventGroup then
            return
          end
          eventGroup.func = value or ""
          self:ClearFocus()
          reloadEventGroupFrameFunc(leaflet, selectedEventGroupIndex)
          --TODO: call func with OPTIONS event
        end)

        -- delete button
        local eventGroupDeleteButton = AceGUI:Create("Button")
        eventGroupDeleteButton:SetText("Delete group")
        dd:AddChild(eventGroupDeleteButton)
        eventGroupDeleteButton:SetCallback("OnClick", function()
          if not eventGroup then
            return
          end
          StaticPopupDialogs["LEAFLET_EVENTGROUP_DELETE"] = {
            text = "Delete event group \""..(eventGroup.events or "").."\"?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
              deleteLeafletEventGroup(leaflet, selectedEventGroupIndex)
              refreshItemDetailTab(container, leaflet, tabId)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
          }
          StaticPopup_Show("LEAFLET_EVENTGROUP_DELETE")
        end)
      end)
      if leaflet.code and leaflet.code.eventgroups then
        if selectedEventGroupIndex and #(leaflet.code.eventgroups) >= selectedEventGroupIndex then
          dd:SetGroup(selectedEventGroupIndex)
        elseif #(leaflet.code.eventgroups) > 0 then
          dd:SetGroup(1)
        else
          dd:SetGroup(0)
        end
      else
        dd:SetGroup(0)
      end
    end
  end
  mainFrame.refreshItemDetailTab = refreshItemDetailTab
  local function refreshItemDetailTabs(leaflet)
    mainFrame.rightPanelACEGroup:ReleaseChildren()
    if leafletsButtons[selectedId] then
      leafletsButtons[selectedId].frame:UnlockHighlight()
    end
    selectedId = leaflet and leaflet.id
    if leaflet then
      leafletsButtons[selectedId].frame:LockHighlight()

      local tabGroup = AceGUI:Create("TabGroup")
      tabGroup:SetLayout("Flow")
      tabGroup:SetTabs({
        { text = "General", value = "general" },
        { text = "Events", value = "events" },
        { text = "Leaf", value = "leaf" },
      })
      mainFrame.rightPanelACEGroup:AddChild(tabGroup)

      tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        refreshItemDetailTab(container, leaflet, group)
      end)
      tabGroup:SelectTab(selectedTab)
    else -- no leaflet selected, show import options
      local importEditBox = AceGUI:Create("MultiLineEditBox")
      importEditBox:SetLabel("Paste and accept to import")
      importEditBox:SetFullWidth(true)
      importEditBox:SetNumLines(6)
      importEditBox:SetText("")
      mainFrame.rightPanelACEGroup:AddChild(importEditBox)
      importEditBox:SetCallback("OnEnterPressed", function(self, event, value)
        self:ClearFocus()
        local data = Leaflets:StringToLeaflet(value)
        if data and data.a == "L4FS" and data.v == SHARE_STRING_VERSION_TAG and data.d then
          if not tonumber(data.d.v) or tonumber(data.d.v) < LEAFLET_VERSION_COMPAT_TAG then
            importEditBox:SetText(format("Leaflet version %d too low, required %d or later", data.d.v, LEAFLET_VERSION_COMPAT_TAG))
            return
          end
          if not verifyDefaultLeafletFields(data.d) then
            importEditBox:SetText("Leaflet corrupted")
            return
          end
          local l = findLeafletById(data.d.id)
          if l then
            StaticPopupDialogs["LEAFLET_IMPORT"] = {
              text = "Import leaflet \""..data.d.name.."\"?",
              button1 = "Overwrite existing",
              button2 = "No",
              button3 = "Create copy",
              OnAccept = function()
                importLeaflet(data.d, true)
              end,
              OnAlt = function()
                importLeaflet(data.d)
              end,
              timeout = 0,
              whileDead = true,
              hideOnEscape = true,
            }
            StaticPopup_Show("LEAFLET_IMPORT")
          else
            StaticPopupDialogs["LEAFLET_IMPORT"] = {
              text = "Import leaflet \""..data.d.name.."\"?",
              button1 = "Yes",
              button2 = "No",
              OnAccept = function()
                importLeaflet(data.d)
              end,
              timeout = 0,
              whileDead = true,
              hideOnEscape = true,
            }
            StaticPopup_Show("LEAFLET_IMPORT")
          end
        else
          importEditBox:SetText("not a valid import string")
        end
      end)
    end
  end
  mainFrame.refreshItemDetailTabs = refreshItemDetailTabs

  ------------------------------------------------
  -- initial population
  ------------------------------------------------
  refreshItemList()
  mainFrame.refreshItemDetailTabs()
end

--------------------------------------------------------------------------------
-- init
--------------------------------------------------------------------------------

function Leaflets:OnEnable()
  self:RegisterComm(COM_CHANNEL)

  --------------------
  -- get all options/upgrade option table
  --------------------
  if not LeafletsOptions then
    LeafletsOptions = DefaultO
  end
  O = LeafletsOptions

  O.addonVersion = C_AddOns.GetAddOnMetadata("Leaflets", "Version")

  loadLeaflets()
end

--------------------------------------------------------------------------------
-- COM
--------------------------------------------------------------------------------

function Leaflets:LeafletToString(leaflet)
  local serialized = LibSerialize:Serialize({a = "L4FS", v = SHARE_STRING_VERSION_TAG, d = leaflet})
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForPrint(compressed)
  return encoded
end
function Leaflets:StringToLeaflet(encoded)
  local decoded = LibDeflate:DecodeForPrint(encoded)
  if not decoded then return end
  local decompressed = LibDeflate:DecompressDeflate(decoded)
  if not decompressed then return end
  local success, data = LibSerialize:Deserialize(decompressed)
  if not success then return end
  return data
end

function Leaflets:Transmit(playerName, data)
  local serialized = LibSerialize:Serialize(data)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
  self:SendCommMessage(COM_CHANNEL, encoded, "WHISPER", playerName)
end

local function COM_RequestLeaflet(playerName, leafletName)
  Leaflets:Transmit(playerName, {
    a = "REQ",
    n = leafletName,
  })
end
local function COM_SendLeaflet(playerName, leafletName)
  cleanupLeafletsLinkedLast5Minutes()
  for _, leaflet in pairs(O.leaflets) do
    if leaflet.name == leafletName then
      if not leafletsLinkedLast5Minutes[leaflet.id] then
        return
      end
      Leaflets:Transmit(playerName, {
        a = "L4FC",
        v = SHARE_STRING_VERSION_TAG,
        d = leaflet,
      })
      break
    end
  end
end

function Leaflets:OnCommReceived(prefix, payload, distribution, sender)
  local decoded = LibDeflate:DecodeForWoWAddonChannel(payload)
  if not decoded then return end
  local decompressed = LibDeflate:DecompressDeflate(decoded)
  if not decompressed then return end
  local success, data = LibSerialize:Deserialize(decompressed)
  if not success then return end

  if not sender:find("-") then
    sender = sender.."-"..myRealm
  end

  --TODO: prevent spam, verify sender before sending them a leaflet

  if type(data) ~= "table" then return end
  if data.a == "REQ" and type(data.n) == "string" then
    print("REQ from", sender, "for", data.n)
    COM_SendLeaflet(sender, data.n)
  elseif data.a == "L4FC" and type(data.d) == "table" then
    if not tonumber(data.d.v) or tonumber(data.d.v) < LEAFLET_VERSION_COMPAT_TAG then
      print("Leaflet version", data.d.v, "too low, required", LEAFLET_VERSION_COMPAT_TAG, "or later")
      return
    end
    if not verifyDefaultLeafletFields(data.d) then
      print(format("Leaflet corrupted (sender: %s)", sender))
      return
    end
    if not hasRequestedLeaflet(sender, data.d.name) then
      return
    end
    print("Leaflet from", sender, "named", data.d.name)
    local l = findLeafletById(data.d.id)
    if l then
      StaticPopupDialogs["LEAFLET_IMPORT"] = {
        text = "Import leaflet \""..data.d.name.."\" from "..sender.."?",
        button1 = "Overwrite existing",
        button2 = "No",
        button3 = "Create copy",
        OnAccept = function()
          importLeaflet(data.d, true)
        end,
        OnAlt = function()
          importLeaflet(data.d)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
      }
      StaticPopup_Show("LEAFLET_IMPORT")
    else
      StaticPopupDialogs["LEAFLET_IMPORT"] = {
        text = "Import leaflet \""..data.d.name.."\" from "..sender.."?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
          importLeaflet(data.d)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
      }
      StaticPopup_Show("LEAFLET_IMPORT")
    end
  end
end

-- prepare incoming links in chat
local function MyAddon_ChatFilter(self, event, msg, author, ...)
  -- Replace [Leaflets:Leaflet Name] with a clickable hyperlink
  msg = msg:gsub("%[Leaflets:(.-)%]", function(itemName)
    return string.format("|HLeaflets:%s:%s|h[%s]|h", author, itemName, itemName)
  end)
  return false, msg, author, ...
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", MyAddon_ChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", MyAddon_ChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", MyAddon_ChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", MyAddon_ChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", MyAddon_ChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", MyAddon_ChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", MyAddon_ChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", MyAddon_ChatFilter)
--ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", MyAddon_ChatFilter)

-- click on a link in chat
hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
  local prefix, author, leafletName = strsplit(":", link)
  if prefix == "Leaflets" then
    local _, _, displayName = text:find("%[(.-)%]")
    print("Clicked on item link:", displayName)
    addRequestedLeaflet(author, leafletName)
    COM_RequestLeaflet(author, leafletName)
  end
end)

--------------------------------------------------------------------------------
-- slash commands
--------------------------------------------------------------------------------

--split string containing quoted and non quoted arguments
--input pattern: (\S+|".+")?(\s+(\S+|".+"))*
--example input: [[arg1 "arg2part1 arg2part2" arg3]]
--example output: {"arg1", "arg2part1 arg2part2", "arg3"}
local function mysplit2(inputstr)
  local i, i1, i2, l, ret, retI = 1, 0, 0, inputstr:len(), {}, 1
  --remove leading spaces
  i1, i2 = inputstr:find("^%s+")
  if i1 then
    i = i2 + 1
  end
  
  while i <= l do
    --find end of current arg
    if (inputstr:sub(i, i)) == "\"" then
      --quoted arg, find end quote
      i1, i2 = inputstr:find("\"%s+", i + 1)
      if i1 then
        --spaces after end quote, more args to follow
        ret[retI] = inputstr:sub(i + 1, i1 - 1)
        retI = retI + 1
        i = i2 + 1
      else
        i1, i2 = inputstr:find("\"$", i + 1)
        if i1 then
          --end of msg
          ret[retI] = inputstr:sub(i + 1, i1 - 1)
          return ret
        else
          -- no end quote found, or end quote followed by no-space-charater found, disregard last arg
          return ret
        end
      end
    else
      --not quoted arg, find next space (if any)
      i1, i2 = inputstr:find("%s+", i + 1)
      if i1 then
        --spaces after arg, more args to follow
        ret[retI] = inputstr:sub(i, i1 - 1)
        retI = retI + 1
        i = i2 + 1
      else
        --end of msg
        ret[retI] = inputstr:sub(i)
        return ret
      end
    end
  end
  
  return ret
end

SLASH_LEAFLETS1 = "/leaf"
SLASH_LEAFLETS2 = "/leaflets"
SlashCmdList["LEAFLETS"] = function(msg, editbox)
  local args = mysplit2(msg or "")

  if string.lower(args[1] or "") == "move" then
  elseif string.lower(args[1] or "") == "hide" then
  elseif string.lower(args[1] or "") == "show" then
  elseif string.lower(args[1] or "") == "reset" then
  elseif string.lower(args[1] or "") == "testcom" then
    --/leaf testcom
    Leaflets:Transmit(UnitName("player"), "tEsT")
  elseif string.lower(args[1] or "") == "addtestleaflet" then
    addLeaflet()
  else
    --print("|cffaaaaffLeaflets |r"..(O.addonVersion or "").." |cffaaaaff(use |r/leaf <option> |cffaaaafffor these options)")
    Leaflets:OpenConfig()
  end
end
