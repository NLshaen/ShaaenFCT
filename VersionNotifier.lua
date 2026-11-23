-- shaaenFCT: in-game GitHub Releases update prompt learned from addon version exchanges.
-- WoW addons cannot make HTTP requests to GitHub. The popup is only triggered
-- after detecting another player running a newer version; publication must
-- be confirmed at the official GitHub Releases page.
local ADDON = ...
local PREFIX = 'SHFCTVER'
local GITHUB_URL = 'https://github.com/NLshaen/ShaaenFCT/releases/latest'
local frame = CreateFrame('Frame')
local popup, versionLabel, currentLabel, urlBox
local popupVersion, pendingVersion
local sessionNotified, repliedTo = {}, {}
local registered, lastBroadcast = false, -1000

local function localVersion()
 local name = ADDON or 'shaaenFCT'
 if C_AddOns and type(C_AddOns.GetAddOnMetadata) == 'function' then
  local ok, value = pcall(C_AddOns.GetAddOnMetadata, name, 'Version')
  if ok and type(value) == 'string' then return value end
 end
 if type(GetAddOnMetadata) == 'function' then
  local ok, value = pcall(GetAddOnMetadata, name, 'Version')
  if ok and type(value) == 'string' then return value end
 end
 return '0.0.0'
end

local function parseVersion(value)
 if type(value) ~= 'string' or #value > 24 then return nil end
 local text = value:match('^v?(%d+%.%d+%.%d+)$')
           or value:match('^v?(%d+%.%d+%.%d+%.%d+)$')
 if not text then return nil end
 local components = {}
 for number in text:gmatch('%d+') do
  components[#components + 1] = tonumber(number)
 end
 return components, text
end

local function isNewer(candidate, installed)
 local a = parseVersion(candidate)
 local b = parseVersion(installed)
 if not a or not b then return false end
 for i = 1, 4 do
  local x, y = a[i] or 0, b[i] or 0
  if x ~= y then return x > y end
 end
 return false
end

local function saved()
 if type(shaaenFCTDB) == 'table' then return shaaenFCTDB end
 return nil
end

local function rectangle(parent, r, g, b, a)
 local texture = parent:CreateTexture(nil, 'BACKGROUND')
 texture:SetAllPoints(parent)
 if texture.SetColorTexture then
  texture:SetColorTexture(r, g, b, a or 1)
 else
  texture:SetTexture('Interface\\Buttons\\WHITE8X8')
  texture:SetVertexColor(r, g, b, a or 1)
 end
 return texture
end

local function caption(parent, text, size, r, g, b)
 local label = parent:CreateFontString(nil, 'OVERLAY')
 label:SetFont('Fonts\\ARIALN.TTF', size or 13, 'OUTLINE')
 label:SetText(text)
 label:SetTextColor(r or 1, g or 1, b or 1)
 return label
end

local function makeButton(parent, text, left, action)
 local button = CreateFrame('Button', nil, parent)
 button:SetSize(116, 29)
 button:SetPoint('BOTTOMLEFT', parent, 'BOTTOMLEFT', left, 16)
 rectangle(button, .17, .19, .24, 1)
 local label = caption(button, text, 12, 1, .74, .48)
 label:SetPoint('CENTER', button, 'CENTER')
 button:SetScript('OnClick', action)
 return button
end

local function createPopup()
 if popup then return popup end
 local p = CreateFrame('Frame', 'ShaaenFCTUpdateNotice', UIParent)
 p:SetSize(460, 242)
 p:SetPoint('CENTER', UIParent, 'CENTER', 0, 75)
 p:SetFrameStrata('DIALOG')
 p:EnableMouse(true)
 p:SetMovable(true)
 if p.SetClampedToScreen then p:SetClampedToScreen(true) end
 p:RegisterForDrag('LeftButton')
 p:SetScript('OnDragStart', function(self) self:StartMoving() end)
 p:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() end)
 rectangle(p, .068, .080, .105, .985)
 local stripe = p:CreateTexture(nil, 'ARTWORK')
 stripe:SetPoint('TOPLEFT', p, 'TOPLEFT', 0, 0)
 stripe:SetPoint('TOPRIGHT', p, 'TOPRIGHT', 0, 0)
 stripe:SetHeight(3)
 if stripe.SetColorTexture then stripe:SetColorTexture(.96, .52, .27, 1)
 else stripe:SetTexture('Interface\\Buttons\\WHITE8X8');stripe:SetVertexColor(.96, .52, .27, 1) end
 local title = caption(p, 'SHAAENFCT  /  GITHUB VERSION CHECK', 17, 1, .64, .35)
 title:SetPoint('TOPLEFT', p, 'TOPLEFT', 20, -18)
 local subtitle = caption(p, 'A player has a newer build. Check for a GitHub release.', 13, .86, .89, .94)
 subtitle:SetPoint('TOPLEFT', p, 'TOPLEFT', 20, -52)
 currentLabel = caption(p, '', 13, .72, .77, .84)
 currentLabel:SetPoint('TOPLEFT', p, 'TOPLEFT', 20, -81)
 versionLabel = caption(p, '', 13, 1, .73, .47)
 versionLabel:SetPoint('TOPLEFT', p, 'TOPLEFT', 240, -81)
 local check = caption(p, 'Check GitHub Releases to confirm a published update:', 12, .80, .83, .88)
 check:SetPoint('TOPLEFT', p, 'TOPLEFT', 20, -115)
 local linkBg = CreateFrame('Frame', nil, p)
 linkBg:SetPoint('TOPLEFT', p, 'TOPLEFT', 19, -139)
 linkBg:SetSize(421, 27)
 rectangle(linkBg, .12, .14, .18, 1)
 local input = CreateFrame('EditBox', nil, linkBg)
 input:SetSize(407, 25)
 input:SetPoint('CENTER', linkBg, 'CENTER')
 input:SetFont('Fonts\\ARIALN.TTF', 12, '')
 input:SetTextColor(1, .70, .44)
 input:SetAutoFocus(false)
 input:SetMaxLetters(150)
 input:SetText(GITHUB_URL)
 input:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
 input:SetScript('OnEditFocusGained', function(self) self:HighlightText() end)
 input:SetScript('OnTextChanged', function(self, userInput)
  if userInput then self:SetText(GITHUB_URL);self:HighlightText() end
 end)
 urlBox = input
 local instruction = caption(p, 'Select the link and press Ctrl+C to copy.', 11, .58, .65, .72)
 instruction:SetPoint('TOPLEFT', p, 'TOPLEFT', 20, -175)
 makeButton(p, 'LATER', 19, function() p:Hide() end)
 makeButton(p, 'COPY LINK', 171, function()
  urlBox:SetFocus()
  urlBox:HighlightText()
 end)
 makeButton(p, 'DISMISS', 324, function()
  local db = saved()
  if db and popupVersion then db.dismissedFCTGithubUpdateVersion = popupVersion end
  p:Hide()
 end)
 p:Hide()
 popup = p
 return p
end

local function showVersion(version, previewOnly)
 if not previewOnly then
  if not isNewer(version, localVersion()) then return end
  local db = saved()
  if db and db.dismissedFCTGithubUpdateVersion == version then return end
  if sessionNotified[version] then return end
  if InCombatLockdown and InCombatLockdown() then
   pendingVersion = version
   return
  end
  sessionNotified[version] = true
 end
 popupVersion = previewOnly and nil or version
 local p = createPopup()
 currentLabel:SetText('INSTALLED:  v' .. localVersion())
 versionLabel:SetText('PEER VERSION:  v' .. version .. (previewOnly and ' (PREVIEW)' or ''))
 p:Show()
end

-- Public entry point for /sfct versiontest. Does not update SavedVariables.
_G.ShaaenFCTTestUpdatePopup = function()
 showVersion('0.7.48', true)
end

local function acceptVersion(version)
 if not isNewer(version, localVersion()) then return end
 local db = saved()
 if not db then return end
 if not isNewer(db.latestKnownFCTGithubVersion, version) then
  db.latestKnownFCTGithubVersion = version
 end
 showVersion(db.latestKnownFCTGithubVersion)
end

local function registerPrefix()
 if registered then return true end
 local f = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
 if type(f) ~= 'function' then return false end
 local ok, result = pcall(f, PREFIX)
 registered = ok and result ~= false
 return registered
end

local function transmit(channel, target)
 if not registerPrefix() then return end
 local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
 if type(f) ~= 'function' then return end
 pcall(f, PREFIX, 'V:' .. localVersion(), channel, target)
end

local function broadcast()
 local now = (type(GetTime) == 'function' and GetTime()) or 0
 if now - lastBroadcast < 30 then return end
 lastBroadcast = now
 if type(IsInGuild) == 'function' and IsInGuild() then transmit('GUILD') end
 if type(IsInGroup) == 'function' and _G.LE_PARTY_CATEGORY_INSTANCE
    and IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE) then
  transmit('INSTANCE_CHAT')
 elseif type(IsInRaid) == 'function' and IsInRaid() then
  transmit('RAID')
 elseif type(IsInGroup) == 'function' and IsInGroup() then
  transmit('PARTY')
 elseif type(GetNumRaidMembers) == 'function' and GetNumRaidMembers() > 0 then
  transmit('RAID')
 elseif type(GetNumPartyMembers) == 'function' and GetNumPartyMembers() > 0 then
  transmit('PARTY')
 end
end

-- Version check is a peer announcement, not a remote GitHub API request.
_G.ShaaenFCTCheckPeerVersion = function()
 local db = saved()
 if db and isNewer(db.latestKnownFCTGithubVersion, localVersion()) then
  showVersion(db.latestKnownFCTGithubVersion)
 end
 broadcast()
end

frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('PLAYER_REGEN_ENABLED')
pcall(frame.RegisterEvent, frame, 'CHAT_MSG_ADDON')
pcall(frame.RegisterEvent, frame, 'GROUP_ROSTER_UPDATE')
frame:SetScript('OnEvent', function(_, event, ...)
 if event == 'ADDON_LOADED' then
  local name = ...
  if name ~= ADDON and name ~= 'shaaenFCT' then return end
  registerPrefix()
 elseif event == 'PLAYER_LOGIN' then
  registerPrefix()
  local db = saved()
  if db and isNewer(db.latestKnownFCTGithubVersion, localVersion()) then
   showVersion(db.latestKnownFCTGithubVersion)
  end
  if C_Timer and type(C_Timer.After) == 'function' then
   C_Timer.After(4, broadcast)
  else
   broadcast()
  end
 elseif event == 'PLAYER_REGEN_ENABLED' then
  if pendingVersion then
   local nextVersion = pendingVersion
   pendingVersion = nil
   showVersion(nextVersion)
  end
 elseif event == 'GROUP_ROSTER_UPDATE' then
  broadcast()
 elseif event == 'CHAT_MSG_ADDON' then
  local prefix, payload, channel, sender = ...
  if prefix ~= PREFIX or type(payload) ~= 'string' then return end
  local version = payload:match('^V:(v?%d+[%d%.]*)$')
  if not version or not parseVersion(version) then return end
  if isNewer(version, localVersion()) then
   acceptVersion(version)
  elseif isNewer(localVersion(), version) and type(sender) == 'string' and sender ~= '' then
   -- Help an older peer learn our version without re-broadcasting to everyone.
   local key = sender .. ':' .. tostring(channel)
   if not repliedTo[key] then
    repliedTo[key] = true
    transmit('WHISPER', sender)
   end
  end
 end
end)
