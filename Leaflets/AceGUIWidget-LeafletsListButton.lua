--[[-----------------------------------------------------------------------------
List Button Container
-------------------------------------------------------------------------------]]
local Type, Version = "LeafletsListButton", 1
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- Lua APIs
local pairs, type = pairs, type

-- WoW APIs
local PlaySound = PlaySound
local CreateFrame, UIParent = CreateFrame, UIParent

--[[-----------------------------------------------------------------------------
Scripts
-------------------------------------------------------------------------------]]
local function Button_OnClick(frame, ...)
  AceGUI:ClearFocus()
  PlaySound(852) -- SOUNDKIT.IG_MAINMENU_OPTION
  frame.obj:Fire("OnClick", ...)
end

local function Control_OnEnter(frame)
  frame.obj:Fire("OnEnter")
end

local function Control_OnLeave(frame)
  frame.obj:Fire("OnLeave")
end

--[[-----------------------------------------------------------------------------
Methods
-------------------------------------------------------------------------------]]
local methods = {
  ["OnAcquire"] = function(self)
    -- restore default values
    self:SetHeight(32)
    self:SetWidth(200)
    self:SetDisabled(false)
    self:SetText()
    self.frame:UnlockHighlight()
  end,

  -- ["OnRelease"] = nil,

  ["SetText"] = function(self, text)
    self.text:SetText(text)
  end,

  ["SetDisabled"] = function(self, disabled)
    self.disabled = disabled
    if disabled then
      self.frame:Disable()
    else
      self.frame:Enable()
    end
  end,
}

--[[-----------------------------------------------------------------------------
Constructor
-------------------------------------------------------------------------------]]
local function Constructor()
  local name = "AceGUI30Button" .. AceGUI:GetNextWidgetNum(Type)
  local frame = CreateFrame("Button", name, UIParent)
  frame:Hide()

  frame:EnableMouse(true)
  frame:SetScript("OnClick", Button_OnClick)
  frame:SetScript("OnEnter", Control_OnEnter)
  frame:SetScript("OnLeave", Control_OnLeave)

  local text = frame:CreateFontString()
  text:SetFontObject("GameFontNormal")
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", 5, -1)
  text:SetPoint("BOTTOMRIGHT", -5, 1)
  text:SetJustifyV("MIDDLE")
  text:SetJustifyH("LEFT")

  frame.bgtexture = frame:CreateTexture(nil, "BACKGROUND")
  frame.bgtexture:SetAllPoints(frame)
  frame.bgtexture:SetColorTexture(0, 0, 0, 0.8)

  frame.highlighttexture = frame:CreateTexture(nil, "HIGHLIGHT")
  frame.highlighttexture:SetAllPoints(frame)
  frame.highlighttexture:SetColorTexture(1, 1, 1, .3)

  --- @type table<string, any>
  local widget = {
    text  = text,
    frame = frame,
    type  = Type,
  }
  for method, func in pairs(methods) do
    widget[method] = func
  end

  return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
