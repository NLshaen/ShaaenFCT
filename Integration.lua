-- shaaenFCT - NL minimap launcher and Game Menu > Options > AddOns.
-- No third-party icon library or font assets required. Loaded AFTER Core.lua.
local ADDON = ...
local minimapButton, quickMenu, optionsPanel
local optionsCategory, initialized
local DEFAULT_ANGLE = 225 -- degrees around the minimap, counter-clockwise
local RADIUS = 78

local function db()
 if type(shaaenFCTDB)=='table' then return shaaenFCTDB end
 return nil
end

local function runCommand(command)
 if SlashCmdList and type(SlashCmdList.SHAAENFCT)=='function' then
  SlashCmdList.SHAAENFCT(command or '')
 end
end

local function whiteTexture(frame,r,g,b,a)
 local tx=frame:CreateTexture(nil,'BACKGROUND')
 tx:SetAllPoints(frame)
 if tx.SetColorTexture then
  tx:SetColorTexture(r,g,b,a or 1)
 else
  tx:SetTexture('Interface\\Buttons\\WHITE8X8')
  tx:SetVertexColor(r,g,b,a or 1)
 end
 return tx
end

local function label(parent,text,size,r,g,b)
 local fs=parent:CreateFontString(nil,'OVERLAY')
 fs:SetFont('Fonts\\ARIALN.TTF',size or 13,'OUTLINE')
 fs:SetText(text)
 fs:SetTextColor(r or .96,g or .96,b or .97)
 return fs
end

local function addonVersion()
 if C_AddOns and type(C_AddOns.GetAddOnMetadata)=='function' then
  local ok,v=pcall(C_AddOns.GetAddOnMetadata,ADDON or 'shaaenFCT','Version')
  if ok and type(v)=='string' and v~='' then return v end
 end
 if type(GetAddOnMetadata)=='function' then
  local ok,v=pcall(GetAddOnMetadata,ADDON or 'shaaenFCT','Version')
  if ok and type(v)=='string' and v~='' then return v end
 end
 return '?'
end

local function placeMinimapButton()
 if not minimapButton or not Minimap then return end
 local cfg=db()
 local angle=(cfg and tonumber(cfg.minimapAngle)) or DEFAULT_ANGLE
 local rad=math.rad(angle)
 minimapButton:ClearAllPoints()
 minimapButton:SetPoint('CENTER',Minimap,'CENTER',math.cos(rad)*RADIUS,math.sin(rad)*RADIUS)
end

local function setMinimapVisible(show)
 local cfg=db()
 if not cfg then return end
 cfg.minimapHidden=not show
 if minimapButton then
  if show then minimapButton:Show();placeMinimapButton() else minimapButton:Hide() end
 end
 if optionsPanel and optionsPanel.refresh then optionsPanel.refresh() end
end

local function resetMinimap()
 local cfg=db()
 if not cfg then return end
 cfg.minimapAngle=DEFAULT_ANGLE
 setMinimapVisible(true)
 placeMinimapButton()
end

-- Use one shared action table, so the menu and the tooltip describe the
-- same commands. Each entry goes through the existing /sfct handler.
local menuActions={
 {'OPEN SETTINGS','open'},
 {'SMART  /  MY DAMAGE','source smart'},
 {'BLIZZARD  /  NATIVE','source player'},
 {'ALL DAMAGE','source all'},
 {'ENABLE ADDON','on'},
 {'DISABLE ADDON','off'},
 {'SHOW STATUS','status'},
}

local function makeQuickMenu()
 if quickMenu then return quickMenu end
 local m=CreateFrame('Frame','shaaenFCTMinimapQuickMenu',UIParent)
 quickMenu=m
 m:SetSize(218,300)
 m:SetFrameStrata('DIALOG')
 if m.SetClampedToScreen then m:SetClampedToScreen(true) end
 m:EnableMouse(true)
 whiteTexture(m,.075,.085,.105,.97)
 local stripe=m:CreateTexture(nil,'ARTWORK')
 stripe:SetPoint('TOPLEFT',0,0);stripe:SetSize(218,2)
 if stripe.SetColorTexture then stripe:SetColorTexture(1,.54,.27,1) else stripe:SetTexture('Interface\\Buttons\\WHITE8X8');stripe:SetVertexColor(1,.54,.27,1) end
 local title=label(m,'NL  /  QUICK COMMANDS',14,1,.68,.39)
 title:SetPoint('TOPLEFT',12,-10)
 for i,entry in ipairs(menuActions) do
  local b=CreateFrame('Button',nil,m)
  b:SetSize(194,29)
  b:SetPoint('TOPLEFT',12,-37-(i-1)*33)
  whiteTexture(b,.14,.16,.20,1)
  local fs=label(b,entry[1],12)
  fs:SetPoint('LEFT',9,0)
  b:RegisterForClicks('LeftButtonUp')
  b:SetScript('OnClick',function()
   m:Hide()
   runCommand(entry[2])
  end)
 end
 local hint=label(m,'/sfct minimap hide  -  Hide icon',10,.67,.71,.76)
 hint:SetPoint('BOTTOMLEFT',12,9)
 m:Hide()
 -- Add to Blizzard's Esc-to-close list if that facility exists.
 if type(UISpecialFrames)=='table' then table.insert(UISpecialFrames,'shaaenFCTMinimapQuickMenu') end
 return m
end

local function showTooltip(self)
 if not GameTooltip then return end
 GameTooltip:SetOwner(self,'ANCHOR_LEFT')
 GameTooltip:AddLine('NL  |cffF3A55AshaaenFCT|r  v'..addonVersion(),1,1,1)
 GameTooltip:AddLine('Left-click: Open settings',.8,.82,.85)
 GameTooltip:AddLine('Right-click: Quick slash commands',.8,.82,.85)
 GameTooltip:AddLine('Drag: Move the minimap icon',.8,.82,.85)
 GameTooltip:AddLine('/sfct  |  /sfct source smart',.96,.65,.36)
 GameTooltip:AddLine('/sfct minimap hide  |  reset',.72,.77,.83)
 GameTooltip:Show()
end

local function updateDrag(self)
 if not Minimap or not GetCursorPosition then return end
 local cfg=db()
 if not cfg then return end
 local cx,cy=Minimap:GetCenter()
 local mx,my=GetCursorPosition()
 if type(cx)~='number' or type(cy)~='number' or type(mx)~='number' or type(my)~='number' then return end
 local scale=Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
 if scale==0 then scale=1 end
 local dx,dy=mx/scale-cx,my/scale-cy
 if dx==0 and dy==0 then return end
 -- math.atan2 exists on WoW's Lua 5.1, but this keeps compatibility with
 -- interpreters that implement only one-argument math.atan.
 local radians
 if math.atan2 then
  radians=math.atan2(dy,dx)
 elseif dx>0 then
  radians=math.atan(dy/dx)
 elseif dx<0 then
  radians=math.atan(dy/dx)+(dy>=0 and math.pi or -math.pi)
 else
  radians=dy>=0 and math.pi/2 or -math.pi/2
 end
 cfg.minimapAngle=(math.deg(radians)+360)%360
 placeMinimapButton()
end

local function createMinimapButton()
 if minimapButton or not Minimap then return end
 local b=CreateFrame('Button','shaaenFCTMinimapButton',Minimap)
 minimapButton=b
 b:SetSize(32,32)
 b:SetFrameStrata('MEDIUM')
 if Minimap.GetFrameLevel and b.SetFrameLevel then
  local ok,level=pcall(Minimap.GetFrameLevel,Minimap)
  if ok and type(level)=='number' then b:SetFrameLevel(level+5) end
 end
 b:RegisterForClicks('LeftButtonUp','RightButtonUp')
 b:RegisterForDrag('LeftButton')
 b:EnableMouse(true)
 whiteTexture(b,.085,.095,.12,.98)
 -- Native minimap ring and built-in font; the icon is an actual NL monogram.
 local border=b:CreateTexture(nil,'OVERLAY')
 border:SetAllPoints(b)
 border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
 local initials=label(b,'NL',15,1,.69,.36)
 initials:SetPoint('CENTER',-1,0)
 b:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
 b:SetScript('OnEnter',showTooltip)
 b:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
 b:SetScript('OnClick',function(_,mouseButton)
  if mouseButton=='RightButton' then
   local m=makeQuickMenu()
   if m:IsShown() then m:Hide() else
    m:ClearAllPoints()
    m:SetPoint('TOPRIGHT',b,'BOTTOMLEFT',-2,-4)
    m:Show()
   end
  else
   if quickMenu then quickMenu:Hide() end
   runCommand('open')
  end
 end)
 b:SetScript('OnDragStart',function(self)
  if quickMenu then quickMenu:Hide() end
  self:SetScript('OnUpdate',updateDrag)
 end)
 b:SetScript('OnDragStop',function(self)
  self:SetScript('OnUpdate',nil)
  placeMinimapButton()
 end)
 placeMinimapButton()
 if db() and db().minimapHidden then b:Hide() else b:Show() end
end

local function gameButton(parent,text,y,action)
 local b=CreateFrame('Button',nil,parent)
 b:SetPoint('TOPLEFT',18,y)
 b:SetSize(320,30)
 whiteTexture(b,.14,.17,.22,1)
 local fs=label(b,text,13,.97,.81,.67)
 fs:SetPoint('LEFT',12,0)
 b.caption=fs
 b:RegisterForClicks('LeftButtonUp')
 b:SetScript('OnClick',action)
 return b
end

local function registerGameOptions()
 if optionsPanel then return end
 local p=CreateFrame('Frame','shaaenFCTGameOptionsPanel',UIParent)
 p.name='shaaenFCT'
 optionsPanel=p
 local title=label(p,'NL  /  SHAAEN FCT',23,1,.66,.37)
 title:SetPoint('TOPLEFT',20,-24)
 local subtitle=label(p,'Floating Combat Text  ·  v'..addonVersion(),12,.73,.78,.85)
 subtitle:SetPoint('TOPLEFT',20,-60)
 local info=label(p,'Open the full addon window to customize fonts and animations.',12,.87,.90,.94)
 info:SetPoint('TOPLEFT',20,-105)
 local note=label(p,'Smart mode needs the Blizzard Combat Log filter: My Actions.',12,.72,.77,.84)
 note:SetPoint('TOPLEFT',20,-132)
 gameButton(p,'OPEN SHAAEN FCT SETTINGS',-180,function() runCommand('open') end)
 gameButton(p,'SMART MODE  /  MY DAMAGE',-224,function() runCommand('source smart') end)
 gameButton(p,'BLIZZARD  /  NATIVE DAMAGE',-268,function() runCommand('source player') end)
 gameButton(p,'ALL DAMAGE  /  UNFILTERED',-312,function() runCommand('source all') end)
 local mini=gameButton(p,'',-366,function()
  local cfg=db()
  if cfg then setMinimapVisible(cfg.minimapHidden) end
 end)
 p.refresh=function()
  local cfg=db()
  if mini and mini.caption then
   mini.caption:SetText(cfg and cfg.minimapHidden and 'SHOW NL MINIMAP ICON' or 'HIDE NL MINIMAP ICON')
  end
 end
 p.refresh()
 local tip=label(p,'Commands: /sfct  ·  /sfct source smart  ·  /sfct minimap reset',11,.67,.73,.79)
 tip:SetPoint('TOPLEFT',20,-433)
 local registered=false
 if Settings and type(Settings.RegisterCanvasLayoutCategory)=='function' and type(Settings.RegisterAddOnCategory)=='function' then
  local ok,cat=pcall(Settings.RegisterCanvasLayoutCategory,p,'shaaenFCT','shaaenFCT')
  if ok and cat then
   local added=pcall(Settings.RegisterAddOnCategory,cat)
   if added then optionsCategory=cat;registered=true end
  end
 end
 if not registered and type(InterfaceOptions_AddCategory)=='function' then
  registered=pcall(InterfaceOptions_AddCategory,p)
 end
 if not registered and DEFAULT_CHAT_FRAME then
  DEFAULT_CHAT_FRAME:AddMessage('|cffffa447shaaenFCT|r  Game Options AddOns API unavailable; /sfct still works.')
 end
end

local baseSlash=SlashCmdList and SlashCmdList.SHAAENFCT
if type(baseSlash)=='function' then
 SlashCmdList.SHAAENFCT=function(msg,...)
  local key=type(msg)=='string' and msg:lower():match('^%s*(.-)%s*$') or ''
  if key=='minimap' or key=='minimap toggle' then
   local cfg=db()
   if cfg then setMinimapVisible(cfg.minimapHidden) end
   return
  elseif key=='minimap show' then setMinimapVisible(true);return
  elseif key=='minimap hide' then setMinimapVisible(false);return
  elseif key=='minimap reset' then resetMinimap();return
  elseif key=='help' then
   if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage('|cffffa447shaaenFCT|r /sfct (settings), /sfct source smart|player|all, /sfct on|off, /sfct status, /sfct minimap show|hide|reset')
   end
   return
  end
  return baseSlash(msg,...)
 end
end

local loader=CreateFrame('Frame')
loader:RegisterEvent('PLAYER_LOGIN')
loader:SetScript('OnEvent',function(self,event)
 if initialized or event~='PLAYER_LOGIN' then return end
 initialized=true
 local cfg=db()
 if not cfg then return end
 if type(cfg.minimapAngle)~='number' then cfg.minimapAngle=DEFAULT_ANGLE end
 if type(cfg.minimapHidden)~='boolean' then cfg.minimapHidden=false end
 -- Keep initialization isolated: a missing game Settings API must not break
 -- the minimap launcher (or the combat-text engine).
 local ok,err=pcall(createMinimapButton)
 if not ok and DEFAULT_CHAT_FRAME then
  DEFAULT_CHAT_FRAME:AddMessage('|cffffa447shaaenFCT|r  Minimap UI error: '..tostring(err))
 end
 local optOK,optError=pcall(registerGameOptions)
 if not optOK and DEFAULT_CHAT_FRAME then
  DEFAULT_CHAT_FRAME:AddMessage('|cffffa447shaaenFCT|r  Game Options UI error: '..tostring(optError))
 end
 self:UnregisterEvent('PLAYER_LOGIN')
end)
