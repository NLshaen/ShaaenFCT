-- shaaenFCT: in-window preview of the ACTUAL combat fonts and trajectory code.
-- This is UI-only. Never reads COMBAT_LOG_EVENT_UNFILTERED or protected values.
local Preview={}

local function colored(parent,r,g,b,a)
 local t=parent:CreateTexture(nil,'BACKGROUND')
 t:SetAllPoints(parent)
 if t.SetColorTexture then t:SetColorTexture(r,g,b,a)
 else t:SetTexture('Interface\\Buttons\\WHITE8X8');t:SetVertexColor(r,g,b,a) end
 return t
end

local function makeText(parent,value,size,r,g,b)
 local fs=parent:CreateFontString(nil,'OVERLAY','GameFontNormal')
 -- Set a valid Blizzard fallback BEFORE any SetText, even on Forever.
 local ok,worked=pcall(fs.SetFont,fs,'Fonts\\ARIALN.TTF',size,'OUTLINE')
 if not ok or worked==false then pcall(fs.SetFontObject,fs,GameFontNormal) end
 fs:SetText(value)
 fs:SetTextColor(r,g,b)
 return fs
end

local function profile(db,critical)
 local mode=db.animationStyle or 'arc'
 local directionField=({arc='direction',popup='popupDirection',float='floatDirection',bounce='bounceDirection'})[mode] or 'direction'
 local direction=db[directionField] or 'alternate'
 local dir=critical and 1 or -1
 if direction=='left' then dir=-1 elseif direction=='right' then dir=1
 elseif direction=='random' then dir=math.random(2)==1 and -1 or 1 end
 local hit={mode=mode,dir=dir,offsetX=db[mode..(critical and 'CritX' or 'NormalX')] or 0,
  offsetY=db[mode..(critical and 'CritY' or 'NormalY')] or 0}
 if mode=='popup' then
  hit.duration=db.popupDuration;hit.startY=db.popupStartY;hit.rise=db.popupRise
  hit.travel=db.popupTravel;hit.peak=db.popupPeak
  hit.intro=db.popupIn/100;hit.hold=db.popupHold/100;hit.fade=db.popupFade
 elseif mode=='float' then
  hit.duration=db.floatDuration;hit.startY=db.floatStartY;hit.rise=db.floatRise
  hit.drift=db.floatDrift;hit.sway=db.floatSway;hit.fade=db.floatFade
 elseif mode=='bounce' then
  hit.duration=db.bounceDuration;hit.startY=db.bounceStartY;hit.rise=db.bounceHeight
  hit.peak=db.bouncePeak;hit.decay=db.bounceDecay
  hit.travel=db.bounceTravel;hit.fade=db.bounceFade
 else
  hit.mode='arc';hit.duration=db.duration;hit.startY=db.startY;hit.rise=db.rise
  hit.arc=db.arc;hit.curve=db.curve;hit.fade=db.fade
 end
 return hit
end

function Preview:Create(parent,getDB,setCombatFont,motionAt,fadeAt)
 local stage=CreateFrame('Frame',nil,parent)
 stage:SetPoint('TOPLEFT',parent,'TOPLEFT',220,-159)
 stage:SetPoint('TOPRIGHT',parent,'TOPRIGHT',-36,-159)
 stage:SetHeight(94)
 colored(stage,.098,.112,.139,.97)
 local border=stage:CreateTexture(nil,'ARTWORK')
 border:SetPoint('TOPLEFT',stage,'TOPLEFT',0,0)
 border:SetPoint('TOPRIGHT',stage,'TOPRIGHT',0,0)
 border:SetHeight(2)
 if border.SetColorTexture then border:SetColorTexture(.91,.52,.28,.85)
 else border:SetTexture('Interface\\Buttons\\WHITE8X8');border:SetVertexColor(.91,.52,.28,.85) end
 local divider=stage:CreateTexture(nil,'ARTWORK')
 divider:SetPoint('TOP',stage,'TOP',0,-20)
 divider:SetPoint('BOTTOM',stage,'BOTTOM',0,8)
 divider:SetWidth(1)
 if divider.SetColorTexture then divider:SetColorTexture(.28,.33,.39,.7)
 else divider:SetTexture('Interface\\Buttons\\WHITE8X8');divider:SetVertexColor(.28,.33,.39,.7) end
 local heading=makeText(stage,'LIVE FONT + ANIMATION PREVIEW',10,1,.67,.38)
 heading:SetPoint('TOPLEFT',stage,'TOPLEFT',11,-6)
 local help=makeText(stage,'NORMAL',9,.69,.75,.83)
 help:SetPoint('TOPLEFT',stage,'TOPLEFT',16,-22)
 local critHelp=makeText(stage,'CRITICAL',9,1,.76,.43)
 critHelp:SetPoint('TOP',stage,'TOP',100,-22)
 local normal=makeText(stage,'2458',24,1,1,1)
 local crit=makeText(stage,'12840',35,1,.86,.12)
 local info=makeText(stage,'',9,.62,.68,.76)
 info:SetPoint('BOTTOM',stage,'BOTTOM',0,4)
 local samples={normal,crit}
 local hits={}
 stage.elapsed=0
 -- The panel is only 94 px tall: trajectories use the same mathematical curves
 -- as nameplate numbers, reduced for preview and clamped to prevent overflow.
 function stage:Refresh(restart)
  local db=getDB()
  if not db then return end
  hits[1]=profile(db,false)
  hits[2]=profile(db,true)
  -- Large configured sizes are reduced to fit within the panel; font faces,
  -- outlines, colors, timing curves and critical size ratio remain accurate.
  local fit=math.min(1,35/math.max(1,db.size*(db.critScale or 1)))
  setCombatFont(normal,math.max(8,db.size*fit),db.font)
  setCombatFont(crit,math.max(8,db.size*(db.critScale or 1)*fit),db.critFont)
  info:SetText('FONT: '..(db.font or 'Arial')..'  /  CRIT: '..(db.critFont or 'Arial')..'  /  '..string.upper(db.animationStyle or 'arc'))
  self._lastScales={}
  if restart then self.elapsed=0 end
 end
 stage:SetScript('OnUpdate',function(self,dt)
  if not hits[1] or not hits[2] then return end
  self.elapsed=self.elapsed+math.min(dt,.08)
  local width=math.max(250,self:GetWidth() or 500)
  for i,fs in ipairs(samples) do
   local hit=hits[i]
   local length=math.max(.25,hit.duration or 1)
   local play=(self.elapsed-(i-1)*.24)%(length+.52)
   local p=play/length
   if p>=1 then fs:SetAlpha(0)
   else
    local x,y,scale=motionAt(hit,p)
    local xoffset=math.max(-66,math.min(66,(x-(hit.offsetX or 0))*.28+(hit.offsetX or 0)*.10))
    local yoffset=math.max(-12,math.min(22,(y-hit.startY-hit.offsetY)*.27+(hit.offsetY or 0)*.06))
    fs:ClearAllPoints()
    fs:SetPoint('CENTER',self,'TOPLEFT',width*(i==1 and .25 or .75)+xoffset,-58+yoffset)
    fs:SetAlpha(fadeAt(hit,p))
    -- Preserve the same Popup/Bounce size changes as the in-game engine.
    if math.abs((scale or 1)-(self._lastScales[i] or 0)) >= .035 then
     local db=getDB()
     local face=i==1 and db.font or db.critFont
     local base=db.size*(i==2 and (db.critScale or 1) or 1)
     local fit=math.min(1,35/math.max(1,db.size*(db.critScale or 1)))
     setCombatFont(fs,math.max(8,math.min(44,base*fit*(scale or 1))),face)
     self._lastScales[i]=scale or 1
    end
   end
  end
 end)
 stage:SetScript('OnShow',function(self) self:Refresh(true) end)
 stage:Refresh(true)
 return stage
end

_G.ShaaenFCTAnimationPreview=Preview
