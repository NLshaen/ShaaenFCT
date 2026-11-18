-- ShaaenFCT independent player-anchored notifications (healing / experience).
-- Separate high-level overlay frames are anchored to the player's visible frame,
-- not parented to it, so Blizzard alpha and clipping cannot hide the text.
local Display={}
local host
local anchors={}
local stats={heal=0,xp=0,reanchors=0,failures=0}

function Display:Configure(parent) host=parent end
local function shown(frame)
 if not frame then return false end
 if not frame.IsShown then return true end
 local ok,result=pcall(frame.IsShown,frame)
 return ok and (not issecretvalue or not issecretvalue(result)) and result==true
end
local function playerFrame()
 if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit)=='function' then
  local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,'player')
  if ok and shown(plate) then return plate end
 end
 for _,name in ipairs({'ElvUF_Player','PlayerFrame'}) do
  local frame=_G[name]
  if shown(frame) then return frame end
 end
 return UIParent
end

function Display:Attach(kind)
 if kind~='heal' and kind~='xp' or not host then return nil end
 local entry=anchors[kind]
 if not entry then
  entry={frame=CreateFrame('Frame',nil,host)}
  anchors[kind]=entry
  entry.frame:SetSize(1,1)
 end
 local target=playerFrame()
 if entry.target~=target then
  local ok=pcall(function()
   local frame=entry.frame
   frame:SetParent(host)
   frame:ClearAllPoints()
   frame:SetFrameStrata('HIGH')
   frame:SetFrameLevel(250)
   frame:SetAlpha(1)
   if target==UIParent then
    frame:SetPoint('CENTER',UIParent,'CENTER',kind=='heal' and -72 or 72,-90)
   else
    frame:SetPoint('CENTER',target,'TOP',kind=='heal' and -42 or 42,6)
   end
   frame:Show()
  end)
  if not ok then stats.failures=stats.failures+1;return nil end
  entry.target=target
  stats.reanchors=stats.reanchors+1
 end
 stats[kind]=stats[kind]+1
 return entry.frame
end
function Display:Statistics() return stats end
_G.ShaaenFCTPlayerDisplay=Display
