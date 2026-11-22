-- shaaenFCT | UI version read from the TOC, game version read from GetBuildInfo()
-- Smart matching and protected-value rendering are based on the tested 0.6.5.3 engine.
local ADDON = ...
-- Never use a hard-coded version in the title bar. The addon version is read
-- from shaaenFCT.toc, the client version from the running WoW Forever build.
local function addonVersion()
 local name=ADDON or 'shaaenFCT'
 if C_AddOns and type(C_AddOns.GetAddOnMetadata)=='function' then
  local ok,value=pcall(C_AddOns.GetAddOnMetadata,name,'Version')
  if ok and type(value)=='string' and value~='' then return value end
 end
 if type(GetAddOnMetadata)=='function' then
  local ok,value=pcall(GetAddOnMetadata,name,'Version')
  if ok and type(value)=='string' and value~='' then return value end
 end
 return 'unknown'
end
-- Read the LIVE client name and version rather than guessing from the addon TOC.
-- Interface 16001 identifies Forever even on early clients without Camelot IDs.
local function wowClientVersions()
 local patch,interface='unknown',0
 if type(GetBuildInfo)=='function' then
  local ok,version,build,date,uiVersion=pcall(GetBuildInfo)
  if ok then
   if type(version)=='string' and version~='' then patch=version end
   if type(uiVersion)=='number' then interface=uiVersion end
  end
 end
 local project=_G.WOW_PROJECT_ID
 local name='WOW'
 if interface==16001 or patch:match('^1%.60%.')
  or (interface==0 and _G.WOW_PROJECT_CAMELOT and project==_G.WOW_PROJECT_CAMELOT) then
  name='WOW FOREVER'
 elseif interface>=11500 and interface<11600 then name='WOW CLASSIC ERA'
 elseif interface>=20500 and interface<20600 then name='WOW TBC CLASSIC'
 elseif interface>=30400 and interface<30500 then name='WOW WRATH CLASSIC'
 elseif interface>=38000 and interface<38100 then name='WOW TITAN REFORGED'
 elseif interface>=40400 and interface<40500 then name='WOW CATA CLASSIC'
 elseif interface>=50500 and interface<50600 then name='WOW MISTS CLASSIC'
 elseif interface>=100000 or (_G.WOW_PROJECT_MAINLINE and project==_G.WOW_PROJECT_MAINLINE) then
  name='WOW RETAIL'
 elseif _G.WOW_PROJECT_CLASSIC and project==_G.WOW_PROJECT_CLASSIC then
  name='WOW CLASSIC'
 end
 return name,patch
end
local engine = CreateFrame('Frame')
local db, window, previewAnchor
local plates, pool, active, overkillPool, statusPool = {}, {}, {}, {}, {}
local healAffixPool={}
-- A final hit uses its own overlay frame anchored to the enemy nameplate.
-- Unlike a child of the plate, this frame survives the plate being hidden.
local fxLayer=CreateFrame('Frame',nil,UIParent)
fxLayer:SetAllPoints(UIParent)
fxLayer:SetFrameStrata('HIGH')
fxLayer:SetFrameLevel(200)
local plateDisplay=_G.ShaaenFCTPlateDisplay
if plateDisplay then plateDisplay:Configure(fxLayer) end
local playerDisplay=_G.ShaaenFCTPlayerDisplay
if playerDisplay then playerDisplay:Configure(fxLayer) end
local playerTextStats={heals=0,xp=0,ignored=0}
local xpPrevious,xpPreviousMax
local plateRenderStats={anchored=0,fallback=0,preview=0}
-- Incoming heals use the same overlay so the player's unit frame is never
-- moved or clipped by the text animation. The heal text has its own anchor.
local overkills={}
local platePositions=setmetatable({}, {__mode='k'})
local killDecorated=setmetatable({}, {__mode='k'})
local plateCacheTick=0
local smartCredits, smartPending = {}, {}
-- Coverage mode keeps a time-bounded list of enemies we have targeted when
-- casting or swinging. Unit combat reports describe the VICTIM, not the
-- attacker, so uncertain hits may only be displayed in solo play.
local coverageTargets=setmetatable({}, {__mode='k'})
local coveragePlateEvents=setmetatable({}, {__mode='k'})
local coverageStats={physical=0,magical=0,unknown=0,credited=0,soloFallback=0,
 targetAlias=0,aliasSkipped=0,zeroSuppressed=0,unverified=0,tracked=0}
local COVERAGE_TARGET_LIFETIME=35
local COVERAGE_ALIAS_WINDOW=.11
local COVERAGE_CAST_SPREAD=.65
local coverageCastUntil=0
local coverageCastAt=0
local coverageCastPlates=setmetatable({}, {__mode='k'})
-- A removed nameplate remains usable as a visual anchor for a short time.
-- This improves late killing-hit delivery without inventing secret damage values.
local recentPlates, pendingKills, plateGuids = {}, {}, {}
local unresolvedKillSignals = {}
local lastShown = setmetatable({}, {__mode='k'})
local lastHits = setmetatable({}, {__mode='k'})
local killScheduled = setmetatable({}, {__mode='k'})
local foreignKillPlates = setmetatable({}, {__mode='k'})
local confirmedPersonalKills = setmetatable({}, {__mode='k'})
local DEATH_GRACE = 1.5
local KILL_RESOLVE_DELAY = .60 -- Give delayed Smart credits/UNIT_COMBAT a chance to pair.
local LAST_HIT_WINDOW = 1.65
local killStats = {late=0, signals=0, labels=0, numeric=0, effects=0, unmatched=0, inferred=0, died=0, removed=0, lateSignals=0}
-- A Smart-matched personal hit on a newly removed nameplate is a conservative
-- fallback when Forever does not provide a usable PARTY_KILL on that mob.
-- It is not an exact proof of a killing blow (a unit can leave nameplate range).
local inferredAt=setmetatable({}, {__mode='k'})
-- A GUID/target token may vanish before PARTY_KILL. Retain the last
-- successfully matched personal hit and a short-lived visible-target hint.
local lastPersonalPlate, lastPersonalAt, lastTargetPlate, lastTargetAt
local killFallbackStats={personal=0,target=0,hiddenAnchor=0,noNameplate=0,noPosition=0}


local smartFlow, filterWarned = false, false
local smartTick, directionIndex = 0, 0
local smartStats = {messages=0, hidden=0, readable=0, oldest=0, queued=0, matched=0, expired=0, discarded=0, failed=0}
local SMART_WINDOW, SMART_RESOLVE, SMART_EXPIRE = 0.24, 0.12, 0.36
-- The combat log on Forever does not provide a readable attacker for each
-- UNIT_COMBAT payload. Never infer a pet hit simply because it struck its target.
-- Only log-matched hits on the player/pet's current targets are considered.
local petStats = {candidates=0, matched=0, fallback=0, failed=0}
local defaultFont = 'Arial'
local defaultUIFont = 'Arial Narrow'
local uiTextEntries = {}
local baseFonts = {
 -- Blizzard only bundles Arial Narrow; prefer an actual Arial from SharedMedia
 -- when present, otherwise use this safe, installed Arial-family fallback.
 ['Arial']='Fonts\\ARIALN.TTF',
 ['Friz Quadrata TT']='Fonts\\FRIZQT__.TTF',
 ['Arial Narrow']='Fonts\\ARIALN.TTF',
 Morpheus='Fonts\\MORPHEUS.TTF',
 Skurri='Fonts\\SKURRI.TTF',
}
local defaults = {
 enabled=true, plateDisplayEnabled=true, discordInvite='', damageSource='coverage', combatLogEnabled=true, petAssist=true, showKillingBlow=true, overkillDuration=1.35, overkillShakeIntensity=50, font=defaultFont, critFont=defaultFont, uiFont=defaultUIFont,
 uiColorStyle='ember', settingsSection='general', windowScale=100, windowOpacity=100,
 outline=true, size=27, critScale=1.5, duration=.9, startY=22,
 rise=65, arc=65, curve=40, fade=55, direction='alternate', animationStyle='arc',
 popupDirection='alternate', floatDirection='alternate', bounceDirection='alternate',
 verticalDirection='up', popupVerticalDirection='up', floatVerticalDirection='up', bounceVerticalDirection='up',
 -- Pixel offsets are independent for each animation style and hit category.
 arcNormalX=0, arcNormalY=0, arcCritX=0, arcCritY=0,
 popupNormalX=0, popupNormalY=0, popupCritX=0, popupCritY=0,
 floatNormalX=0, floatNormalY=0, floatCritX=0, floatCritY=0,
 bounceNormalX=0, bounceNormalY=0, bounceCritX=0, bounceCritY=0,
 -- Animation profiles are independent and persist in SavedVariables.
 popupDuration=.85, popupStartY=28, popupRise=35, popupPeak=1.8,
 popupIn=18, popupHold=22, popupFade=64, popupTravel=28,
 floatDuration=1.15, floatStartY=32, floatRise=110,
 floatDrift=24, floatSway=15, floatFade=56,
 bounceDuration=1.0, bounceStartY=27, bounceHeight=62,
 bouncePeak=1.5, bounceDecay=3.0, bounceFade=62, bounceTravel=28
}
local ranges = {
 duration={.3,2.5,.05,2}, startY={5,100,1,0}, rise={0,160,1,0},
 arc={0,150,1,0}, curve={0,120,1,0}, fade={0,95,1,0},
 size={10,70,1,0}, critScale={1,2.5,.05,2}, overkillDuration={.5,3,.05,2}, overkillShakeIntensity={0,100,1,0},
 popupDuration={.3,2.5,.05,2}, popupStartY={5,110,1,0}, popupRise={0,140,1,0},
 popupPeak={1,3,.05,2}, popupIn={5,55,1,0}, popupHold={0,60,1,0}, popupFade={0,95,1,0},
 popupTravel={0,120,1,0},
 floatDuration={.3,3,.05,2}, floatStartY={5,110,1,0}, floatRise={0,200,1,0},
 floatDrift={0,120,1,0}, floatSway={0,80,1,0}, floatFade={0,95,1,0},
 bounceDuration={.3,3,.05,2}, bounceStartY={5,110,1,0}, bounceHeight={0,150,1,0},
 bouncePeak={1,2.5,.05,2}, bounceDecay={1,7,.25,2}, bounceFade={0,95,1,0},
 bounceTravel={0,120,1,0}
}
-- Signed offsets are intentionally in pixels: left/down are negative.
-- Unlike secret combat amounts, these are normal user-provided numbers.
for _,style in ipairs({'arc','popup','float','bounce'}) do
 for _,suffix in ipairs({'NormalX','NormalY','CritX','CritY'}) do
  ranges[style..suffix]={-250,250,1,0}
 end
end
local function say(message)
 if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffffa447shaaenFCT|r  '..tostring(message)) end
end
local function colorTexture(parent,r,g,b,a)
 local t=parent:CreateTexture(nil,'BACKGROUND')
 t:SetAllPoints()
 if t.SetColorTexture then t:SetColorTexture(r,g,b,a or 1)
 else t:SetTexture('Interface\\Buttons\\WHITE8X8');t:SetVertexColor(r,g,b,a or 1) end
 return t
end
local function fixedTexture(parent,point,x,y,width,height,r,g,b,a)
 local t=parent:CreateTexture(nil,'ARTWORK')
 t:SetPoint(point,x,y);t:SetSize(width,height)
 if t.SetColorTexture then t:SetColorTexture(r,g,b,a or 1)
 else t:SetTexture('Interface\\Buttons\\WHITE8X8');t:SetVertexColor(r,g,b,a or 1) end
 return t
end
local function media()
 if shaaenFCTMedia then return shaaenFCTMedia end
 if LibStub then
  local ok,lib=pcall(function() return LibStub('LibSharedMedia-3.0',true) end)
  if ok then return lib end
 end
end
-- Preferred names are virtual selections, NOT bundled font files. The actual
-- font must be supplied by an installed LibSharedMedia addon, except Blizzard's
-- own four fonts. Ellesmere's standard Expressway face is exposed under a clear
-- alias. No font files are redistributed with shaaenFCT.
local featuredFonts={
 {name='Numen', aliases={'Numen','Numen Regular','Numen Font'}},
 {name='Ellesmere (Expressway)', aliases={'Ellesmere','Expressway','Expressway Regular'}},
 {name='BigDam', aliases={'BigDam','Big Dam','BigDam Regular'}},
 {name='Expressway Bold', aliases={'Expressway Bold'}},
 {name='Inter Tight', aliases={'Inter Tight','InterTight'}},
 {name='Poppins', aliases={'Poppins'}},
 {name='Roboto Condensed', aliases={'Roboto Condensed','RobotoCondensed'}},
 {name='Russo One', aliases={'Russo One'}},
 {name='Gotham Narrow', aliases={'Gotham Narrow'}},
 {name='Fira Sans Bold', aliases={'Fira Sans Bold','FiraSans Bold'}},
}
local function fontToken(name)
 if type(name)~='string' then return '' end
 return name:lower():gsub('[^%w]','')
end
local registeredFontsCache,registeredFontsAt
local function sharedFonts(force)
 local now=(type(GetTime)=='function' and GetTime()) or 0
 -- Popup/Bounce animations can call SetFont every frame. Reuse the registry
 -- snapshot instead of iterating all SharedMedia fonts on every tick.
 if not force and registeredFontsCache and now-registeredFontsAt<5 then
  return registeredFontsCache[1],registeredFontsCache[2]
 end
 local lib=media()
 if not lib then
  registeredFontsCache={{},{}}
  registeredFontsAt=now
  return registeredFontsCache[1],registeredFontsCache[2]
 end
 local ok,names=pcall(lib.List,lib,'font')
 if not ok or type(names)~='table' then return {},{} end
 -- Fetch paths as the authoritative source; the registry might contain a
 -- font name whose underlying provider was removed or hasn't loaded yet.
 local paths,byToken={},{}
 for _,name in ipairs(names) do
  if type(name)=='string' then
   local got,path=pcall(lib.Fetch,lib,'font',name,true)
   if got and type(path)=='string' and path~='' then
    paths[name]=path
    local token=fontToken(name)
    if not byToken[token] then byToken[token]=path end
   end
  end
 end
 registeredFontsCache={paths,byToken}
 registeredFontsAt=now
 return paths,byToken
end
local function resolveRegistered(name,paths,byToken)
 if type(name)~='string' then return nil end
 if paths[name] then return paths[name] end
 return byToken[fontToken(name)]
end
local function resolveFontPath(name,paths,byToken)
 name=name or defaultFont
 paths=paths or {}
 byToken=byToken or {}
 -- Do not override a real, user-installed Arial with the built-in fallback.
 if name=='Arial' then return resolveRegistered('Arial',paths,byToken) or baseFonts['Arial'] end
 if baseFonts[name] then return baseFonts[name] end
 local matched=resolveRegistered(name,paths,byToken)
 if matched then return matched end
 for _,entry in ipairs(featuredFonts) do
  if name==entry.name then
   for _,alias in ipairs(entry.aliases) do
    local path=resolveRegistered(alias,paths,byToken)
    if path then return path end
   end
  end
 end
 return nil
end
local function resolveFont(name)
 local paths,byToken=sharedFonts()
 return resolveFontPath(name,paths,byToken) or baseFonts[defaultFont]
end
local function availableFonts()
 local list,used={},{}
 local paths,byToken=sharedFonts(true)
 local function add(name,group,available)
  if not used[name] then
   list[#list+1]={name=name,group=group,available=available}
   used[name]=true
  end
 end
 -- These three remain visible even if their provider isn't installed.
 for i,entry in ipairs(featuredFonts) do
  local available=resolveFontPath(entry.name,paths,byToken)~=nil
  if i<=3 or available then add(entry.name,'FEATURED',available) end
 end
 local builtins={}
 for name in pairs(baseFonts) do builtins[#builtins+1]=name end
 table.sort(builtins)
 for _,name in ipairs(builtins) do add(name,'BLIZZARD',true) end
 local extras={}
 for name in pairs(paths) do
  if not used[name] then extras[#extras+1]=name end
 end
 table.sort(extras,function(a,b) return a:lower()<b:lower() end)
 for _,name in ipairs(extras) do
  local localFont=shaaenFCTMedia and type(shaaenFCTMedia.IsLocal)=='function' and shaaenFCTMedia:IsLocal(name)
  add(name,localFont and 'LOCAL CUSTOM FONTS' or 'SHARED MEDIA',true)
 end
 return list
end
local function setFont(fs,size,name)
 local outline=db and db.outline and 'OUTLINE' or ''
 -- A broken/missing file must not abort panel construction or combat rendering.
 local ok,result=pcall(fs.SetFont,fs,resolveFont(name),size,outline)
 if not ok or result==false then
  pcall(fs.SetFont,fs,baseFonts[defaultFont],size,'OUTLINE')
 end
 fs:SetShadowColor(0,0,0,.9);fs:SetShadowOffset(1,-1)
end
-- Render damage modifiers (GLANCING / BLOCKED) in a separate FontString.
-- The numeric value can be protected/secret; NEVER concatenate it with text.
local function releaseStatusLabel(hit)
 if hit and hit.statusLabel then
  local label=hit.statusLabel
  label:Hide()
  label:ClearAllPoints()
  statusPool[#statusPool+1]=label
  hit.statusLabel=nil
 end
end
local function createStatusLabel(fs,fontName,baseSize,status)
 local label=table.remove(statusPool)
 if not label then label=fxLayer:CreateFontString(nil,'OVERLAY') end
 label:SetParent(fxLayer)
 label:ClearAllPoints()
 label:SetPoint('BOTTOM',fs,'TOP',0,1)
 setFont(label,math.max(9,baseSize*.40),fontName)
 label:SetText(status)
 if status=='BLOCKED' then label:SetTextColor(.67,.71,.77)
 else label:SetTextColor(.77,.81,.86) end
 label:SetAlpha(1)
 label:Show()
 return label
end
-- Healing labels cannot concatenate their amount: WoW Forever can make
-- UNIT_COMBAT numbers secret. A separate plus and HP label follow the same
-- FontString, preserving secret values without reading or converting them.
local function releaseHealAffixes(hit)
 if not hit then return end
 for _,part in ipairs({hit.healPrefix,hit.healSuffix}) do
  if part then
   part:Hide();part:ClearAllPoints();part:SetParent(UIParent)
   healAffixPool[#healAffixPool+1]=part
  end
 end
 hit.healPrefix=nil;hit.healSuffix=nil
end
local function makeHealAffix(fs,text,fontName,baseSize,side)
 local part=table.remove(healAffixPool)
 if not part then part=UIParent:CreateFontString(nil,'OVERLAY','GameFontNormal') end
 part:SetParent(fs:GetParent())
 part:ClearAllPoints()
 part:SetPoint(side=='prefix' and 'RIGHT' or 'LEFT',fs,side=='prefix' and 'LEFT' or 'RIGHT',side=='prefix' and -3 or 3,0)
 setFont(part,math.max(10,baseSize*.8),fontName)
 part:SetText(text)
 part:SetTextColor(.30,1,.43)
 part:SetAlpha(1);part:Show()
 return part
end
local function releaseOverkill(fx)
 fx.frame:Hide();fx.frame:ClearAllPoints();fx.frame:SetAlpha(1)
 overkillPool[#overkillPool+1]=fx.frame
end
local function clearOverkills()
 for i=#overkills,1,-1 do
  releaseOverkill(overkills[i])
  overkills[i]=nil
 end
end
local function clearNumbers()
 for i=#active,1,-1 do
  local hit=active[i]
  releaseStatusLabel(hit)
  releaseHealAffixes(hit)
  if hit.fs then hit.fs:Hide();hit.fs:SetParent(UIParent);pool[#pool+1]=hit.fs end
  active[i]=nil
 end
 clearOverkills()
 if plateDisplay then plateDisplay:Clear() end
end
local function clearQueues()
 smartCredits,smartPending={},{}
 coverageTargets=setmetatable({}, {__mode='k'})
 coveragePlateEvents=setmetatable({}, {__mode='k'})
 coverageCastUntil=0
 coverageCastAt=0
 coverageCastPlates=setmetatable({}, {__mode='k'})
 pendingKills={}
 unresolvedKillSignals={}
 foreignKillPlates=setmetatable({}, {__mode='k'})
 confirmedPersonalKills=setmetatable({}, {__mode='k'})
end
local function enableNative()
 local key='floatingCombatTextCombatDamage_v2'
 local get=GetCVar or (C_CVar and C_CVar.GetCVar)
 local set=SetCVar or (C_CVar and C_CVar.SetCVar)
 if type(get)=='function' then
  local ok,value=pcall(get,key)
  if ok and value=='1' then return end
 end
 if type(set)=='function' then
  local ok=pcall(set,key,'1')
  if ok then return end
 end
 if not filterWarned then
  filterWarned=true
  say('Unable to enable Blizzard combat text automatically: /console floatingCombatTextCombatDamage_v2 1')
 end
end
local function disableNative()
 local set=SetCVar or (C_CVar and C_CVar.SetCVar)
 if type(set)=='function' then pcall(set,'floatingCombatTextCombatDamage_v2','0') end
end
local function enableFilteredLog()
 if not db or db.combatLogEnabled==false then return end
 if C_CombatLog and type(C_CombatLog.SetFilteredEventsEnabled)=='function' then
  pcall(C_CombatLog.SetFilteredEventsEnabled,true)
 end
end
local function setSource(source)
 if source~='coverage' and source~='player' and source~='all' then return end
 db.damageSource=source
 if source=='coverage' then db.plateDisplayEnabled=true end
 clearNumbers();clearQueues()
 if db.enabled and source=='player' then enableNative() else disableNative() end
 if source=='coverage' then enableFilteredLog() end
end
-- Do not read, compare, stringify or calculate with protected combat amounts.
-- Only unrelated UI coordinates and unit IDs are inspected when safely readable.
local function safeValue(value)
 return not (issecretvalue and issecretvalue(value))
end
local function safeGUID(unit)
 if type(UnitGUID)~='function' then return nil end
 local ok,guid=pcall(UnitGUID,unit)
 if ok and safeValue(guid) and type(guid)=='string' then return guid end
end
local function isUnitTarget(unit)
 if type(UnitIsUnit)~='function' then return false end
 local ok,same=pcall(UnitIsUnit,unit,'target')
 return ok and safeValue(same) and same==true
end
-- UNIT_COMBAT identifies the victim but not the attacker on WoW Forever.
-- In particular, another player's pet hitting our pet's target is *not* proof
-- of an action by our own pet. Restrict Smart matching to our target or our
-- pet's target, and require a filtered combat-log credit as well.
local function petTargetsUnit(unit)
 if not db or not db.petAssist then return false end
 local petExists=safeGUID('pet')~=nil
 if type(UnitExists)=='function' then
  local ok,exists=pcall(UnitExists,'pet')
  if ok and safeValue(exists) and exists==true then petExists=true end
 end
 if not petExists then return false end
 if type(UnitIsUnit)=='function' then
  local ok,same=pcall(UnitIsUnit,unit,'pettarget')
  if ok and safeValue(same) and same==true then return true end
 end
 local enemyGUID,petTargetGUID=safeGUID(unit),safeGUID('pettarget')
 return enemyGUID~=nil and petTargetGUID~=nil and enemyGUID==petTargetGUID
end
local function isPersonalTarget(unit,plate)
 if isUnitTarget(unit) then return true,false end
 if petTargetsUnit(unit) then return true,true end
 -- Late UNIT_COMBAT after death may lose its nameplate unit token. The cached
 -- player's target is valid only momentarily; never use an unrelated plate.
 if lastTargetPlate==plate and lastTargetAt and GetTime()-lastTargetAt<=.30 then
  return true,false
 end
 return false,false
end
-- Nameplate alias resolution never reads secret damage data. It only maps
-- the familiar `target` token to an existing nameplate frame.
local function livePlateForUnit(unit)
 if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit)=='function' then
  local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,unit)
  if ok and plate then return plate end
 end
 local guid=safeGUID(unit)
 for token,plate in pairs(plates) do
  if type(UnitIsUnit)=='function' then
   local ok,same=pcall(UnitIsUnit,token,unit)
   if ok and safeValue(same) and same==true then return plate end
  end
  if guid and (plateGuids[token]==guid or safeGUID(token)==guid) then return plate end
 end
end
local function coverageIsSolo()
 if type(IsInGroup)=='function' then
  local ok,grouped=pcall(IsInGroup)
  if not ok or not safeValue(grouped) then return false end
  if grouped then return false end
 end
 if type(IsInRaid)=='function' then
  local ok,raid=pcall(IsInRaid)
  if not ok or not safeValue(raid) then return false end
  if raid then return false end
 end
 return true
end
local function coverageTrack(unit,spellCast)
 if not db or db.damageSource~='coverage' or not safeValue(unit) or type(unit)~='string' then return end
 if spellCast then
  coverageCastAt=GetTime()
  coverageCastUntil=coverageCastAt+COVERAGE_CAST_SPREAD
  coverageCastPlates=setmetatable({}, {__mode='k'})
  -- Snapshot the nameplates present at cast time; a newly recycled unit
  -- must not inherit this short AoE attribution window.
  for _,candidate in pairs(plates) do coverageCastPlates[candidate]=true end
 end
 local plate=livePlateForUnit(unit)
 if not plate then return end
 coverageTargets[plate]=GetTime()+COVERAGE_TARGET_LIFETIME
 coverageStats.tracked=coverageStats.tracked+1
end
local function coverageOwnTarget(unit,plate)
 local authorized=isPersonalTarget(unit,plate)
 if authorized then return true end
 local now=GetTime()
 local expires=coverageTargets[plate]
 if expires~=nil and expires>=now then return true end
 -- A spell can hit multiple nameplates at once. A very short, post-cast
 -- window allows the first impact on each extra enemy to establish tracking
 -- for subsequent DoT ticks. This is a solo-only visual fallback, not proof
 -- of personal ownership of victim-only UNIT_COMBAT events.
 if now<=coverageCastUntil and coverageCastPlates[plate] and unit:match('^nameplate%d+$') then
  if type(UnitCanAttack)=='function' then
   local ok,hostile=pcall(UnitCanAttack,'player',unit)
   if ok and safeValue(hostile) and hostile==false then return false end
  end
  coverageTargets[plate]=now+COVERAGE_TARGET_LIFETIME
  coverageStats.tracked=coverageStats.tracked+1
  return true
 end
 return false
end
local function coverageKind(school,notice)
 if notice then return 'unknown' end
 if safeValue(school) and type(school)=='number' then
  if school==1 then return 'physical' end
  if school>1 then return 'magical' end
 end
 return 'unknown'
end
local function coverageRecord(kind)
 coverageStats[kind]=(coverageStats[kind] or 0)+1
end
local function coverageAliasDuplicate(plate,action,now)
 local seen=coveragePlateEvents[plate]
 return seen and now-seen.at<=COVERAGE_ALIAS_WINDOW and seen.action==action
end
local function safeDead(unit)
 if type(UnitIsDead)~='function' then return false end
 local ok,dead=pcall(UnitIsDead,unit)
 return ok and safeValue(dead) and dead==true
end
local function getPosition(plate)
 if not plate or not plate.GetCenter or not plate.GetTop then return nil end
 local ok,x,y,scale,uiScale=pcall(function()
  local cx=plate:GetCenter()
  local top=plate:GetTop()
  local sc=plate.GetEffectiveScale and plate:GetEffectiveScale() or 1
  local usc=UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  return cx,top,sc,usc
 end)
 if not ok or not (safeValue(x) and safeValue(y) and safeValue(scale) and safeValue(uiScale)) then return nil end
 if type(x)~='number' or type(y)~='number' or type(scale)~='number' or type(uiScale)~='number' or uiScale==0 then return nil end
 return {x=x*scale/uiScale,y=y*scale/uiScale}
end
local function rememberPosition(plate)
 if not plate then return nil end
 local position=getPosition(plate)
 if position then platePositions[plate]=position end
 return position or platePositions[plate]
end
local function positionForPlate(plate)
 local recent
 for _,entry in pairs(recentPlates) do
  if entry.plate==plate and GetTime()-entry.at<DEATH_GRACE then recent=entry.position;break end
 end
 return recent or platePositions[plate] or rememberPosition(plate)
end
local function recentForPlate(plate)
 local now=GetTime()
 for _,entry in pairs(recentPlates) do
  if entry.plate==plate and now-entry.at<DEATH_GRACE then return entry end
 end
end
local function anchorNumber(fs,hit,x,y)
 if hit.detached and hit.position then
  fs:SetPoint('CENTER',fxLayer,'BOTTOMLEFT',hit.position.x+x,hit.position.y+y)
 elseif hit.anchor then
  fs:SetPoint('CENTER',hit.anchor,'CENTER',x,y)
 elseif hit.position then
  fs:SetPoint('CENTER',UIParent,'BOTTOMLEFT',hit.position.x+x,hit.position.y+y)
 else
  fs:SetPoint('CENTER',hit.plate,'TOP',x,y)
 end
end
-- All trajectory arithmetic uses user configuration and elapsed time only.
-- Protected damage values never enter this function.
local function verticalMotionY(hit,value)
 local start=hit.startY or 0
 return start+(value-start)*(hit.vdir or 1)
end
local function profileMotionAt(hit,p)
 local mode=hit.mode or 'arc'
 if mode=='popup' then
  local intro=math.max(.05,hit.intro or .18)
  local hold=math.min(.9,hit.hold or .22)
  local peak=hit.peak or 1.8
  local scale
  if p<intro then
   local t=p/intro
   scale=1+(peak-1)*(1-(1-t)*(1-t))
  elseif p<intro+hold then
   scale=peak
  else
   local t=math.min(1,(p-intro-hold)/math.max(.05,1-intro-hold))
   scale=1+(peak-1)*(1-t)*(1-t)
  end
  local travel=1-(1-p)*(1-p)
  return hit.dir*(hit.travel or 0)*travel,verticalMotionY(hit,hit.startY+hit.rise*travel),scale
 elseif mode=='float' then
  local travel=1-math.pow(1-p,1.55)
  local sway=math.sin(p*math.pi*3)*(hit.sway or 0)*(1-p*.25)
  return hit.dir*((hit.drift or 0)*p+sway),verticalMotionY(hit,hit.startY+hit.rise*travel),1
 elseif mode=='bounce' then
  local decay=hit.decay or 3
  local bounce=math.abs(math.sin(3.5*math.pi*p))*math.exp(-decay*p)
  local travel=1-math.exp(-4*p)
  local lift=hit.rise*travel+hit.rise*.4*bounce
  local scale=1+((hit.peak or 1.5)-1)*bounce
  return hit.dir*(hit.travel or 0)*(.75*p+.25*bounce),verticalMotionY(hit,hit.startY+lift),scale
 else
  return hit.dir*hit.arc*p,verticalMotionY(hit,hit.startY+hit.rise*p+hit.curve*4*p*(1-p)),1
 end
end
-- Apply positional offsets to every style, whether attached to a nameplate
-- or rendered in the independent post-death overlay.
local function motionAt(hit,p)
 local x,y,scale=profileMotionAt(hit,p)
 return x+(hit.offsetX or 0),y+(hit.offsetY or 0),scale
end
local function fadeAt(hit,p)
 local fadeStart=math.min(.95,math.max(0,(hit.fade or 55)/100))
 if p<=fadeStart then return 1 end
 return math.max(0,1-(p-fadeStart)/(1-fadeStart))
end

-- Only the dedicated final-hit overlay shakes: no movement of the nameplate
-- or ordinary damage numbers. One second of soft oscillation and a quadratic
-- ease-out avoid the sudden, harsh 0.42-second shake used in v0.7.18.
local OVERKILL_SHAKE_TIME=1.0
local overkillShakeAmplitudes={
 light={2.5,1.25},
 medium={5,2.5},
 strong={8,4}
}
local function overkillShakeAt(t,intensity)
 if t<=0 or t>=OVERKILL_SHAKE_TIME then return 0,0 end
 -- 0 = no shake, 50 = the old medium preset, 100 = maximum.
 local percent=type(intensity)=='number' and math.max(0,math.min(100,intensity)) or 50
 local factor=percent/50
 local amplitude={overkillShakeAmplitudes.medium[1]*factor,overkillShakeAmplitudes.medium[2]*factor}
 local progress=t/OVERKILL_SHAKE_TIME
 local strength=1-progress
 strength=strength*strength
 -- Two low-frequency continuous sine waves: small, smoothly fading motion.
 return math.sin(t*math.pi*12)*amplitude[1]*strength,
        math.sin(t*math.pi*15)*amplitude[2]*strength
end

-- The independent frame follows the living plate, then freezes at the last
-- valid top-center position if Blizzard removes/recycles the nameplate.
-- Shake offsets are identical in both anchoring modes; never use screen center.
local function placeOverkill(fx,rise)
 local x=fx.shakeX or 0
 local y=(fx.baseY or 8)+(rise or 0)+(fx.shakeY or 0)
 fx.frame:ClearAllPoints()
 if fx.frozen then
  if not fx.position then return false end
  fx.frame:SetPoint('CENTER',fxLayer,'BOTTOMLEFT',fx.position.x+x,fx.position.y+y)
 else
  fx.frame:SetPoint('CENTER',fx.plate,'TOP',x,y)
 end
 return true
end
local function freezeOverkillsForPlate(plate,position)
 for _,fx in ipairs(overkills) do
  if fx.plate==plate and not fx.frozen then
   local saved=position or platePositions[plate] or fx.position or rememberPosition(plate)
   if saved then
    fx.position=saved;fx.frozen=true
    if not pcall(placeOverkill,fx,fx.rise or 0) then fx.expired=true end
   else
    -- Without a known world position, hiding is safer than jumping to center.
    fx.expired=true;killFallbackStats.noPosition=killFallbackStats.noPosition+1
   end
  end
 end
end

local function detachNumbers(plate,position)
 for _,hit in ipairs(active) do
  if hit.plate==plate and not hit.detached then
   local lastPosition=position or platePositions[plate] or hit.position
   hit.detached=true
   hit.anchor=nil
   if lastPosition then
    hit.position=lastPosition
    hit.fs:SetParent(fxLayer)
    hit.fs:ClearAllPoints()
    local p=math.min(1,hit.t/math.max(.1,hit.duration))
    local x,y=motionAt(hit,p)
    anchorNumber(hit.fs,hit,x,y)
   else
    -- Never let an old hit follow an unrelated unit when a plate is reused.
    hit.suppressed=true
    hit.fs:Hide()
    releaseStatusLabel(hit)
    hit.fs:SetParent(fxLayer)
   end
  end
 end
end
local function rememberRemoved(unit)
 local plate=plates[unit]
 if not plate then return end
 local now=GetTime()
 local wasTarget=isUnitTarget(unit) or (lastTargetPlate==plate and now-(lastTargetAt or 0)<.8)
 if wasTarget then lastTargetPlate,lastTargetAt=plate,now end
 local entry={unit=unit,plate=plate,at=now,guid=safeGUID(unit) or plateGuids[unit],wasTarget=wasTarget,position=platePositions[plate] or rememberPosition(plate)}
 recentPlates[unit]=entry
 freezeOverkillsForPlate(plate,entry.position)
 detachNumbers(plate,entry.position)
end
-- A killing blow on Forever may arrive only through a soft-target token
-- after the nameplate is removed. Require a readable dead flag and a
-- recently removed plate. Smart still requires a matching own-action credit.
local function lastRemoved(guid,needTarget)
 local now=GetTime()
 local best,bestScore
 for _,entry in pairs(recentPlates) do
  if now-entry.at<DEATH_GRACE then
   local score=now-entry.at
   if guid and entry.guid and guid==entry.guid then score=score-100
   elseif guid and entry.guid and guid~=entry.guid then score=score+100
   elseif entry.wasTarget then score=score-.20 end
   if not needTarget or entry.wasTarget or (guid and entry.guid and guid==entry.guid) then
    if not bestScore or score<bestScore then best,bestScore=entry,score end
   end
  end
 end
 if guid and best and best.guid and best.guid~=guid then return nil end
 return best
end
local function findLatePlateForUnit(unit)
 if not safeDead(unit) then return nil end
 local guid=safeGUID(unit)
 -- Only use the recently removed target or a GUID match, not a random corpse.
 return lastRemoved(guid,true)
end

-- A frame created for each final hit, containing a FontString, independent of
-- both the original damage number and the nameplate frame's lifecycle.
-- It is placed at the TOP of the matching enemy plate, not the unit_target UI.
local function makeOverkillFrame()
 local frame=table.remove(overkillPool)
 if not frame then
  frame=CreateFrame('Frame',nil,fxLayer)
  frame:SetSize(160,48)
  local number=frame:CreateFontString(nil,'OVERLAY')
  number:SetPoint('CENTER',frame,'CENTER',0,0)
  frame.number=number
 end
 return frame
end

-- The final amount may be secret; pass it directly to SetText inside pcall.
-- A detached plate needs a cached on-screen position, otherwise skip the FX.
local function spawnFinalNumberAt(info,plate,forcedPosition,forceFrozen)
 if not info or not plate then
  killFallbackStats.noNameplate=killFallbackStats.noNameplate+1
  return false
 end
 local recent=recentForPlate(plate)
 local shown=true
 if plate.IsShown then
  local ok,value=pcall(plate.IsShown,plate)
  shown=ok and safeValue(value) and value==true
 end
 local frozen=forceFrozen or recent~=nil or not shown
 local position=forcedPosition or (recent and recent.position) or platePositions[plate] or (info and info.position)
 if not frozen then position=rememberPosition(plate) or position end
 if frozen and not position then
  killFallbackStats.noPosition=killFallbackStats.noPosition+1
  return false
 end
 local frame=makeOverkillFrame()
 local fx={frame=frame,plate=plate,position=position,frozen=frozen,
  baseY=8,rise=0,t=0,duration=db.overkillDuration}
 local ok=pcall(function()
  frame:SetParent(fxLayer)
  frame:SetAlpha(1)
  setFont(frame.number,db.size*db.critScale,db.critFont)
  frame.number:SetTextColor(1,.85,.20)
  frame.number:SetText(info.amount)
  if not placeOverkill(fx,0) then error('nameplate position unavailable') end
  frame:Show()
 end)
 if not ok then
  releaseOverkill(fx)
  smartStats.failed=smartStats.failed+1
  return false
 end
 overkills[#overkills+1]=fx
 if frozen then killFallbackStats.hiddenAnchor=killFallbackStats.hiddenAnchor+1 end
 killStats.effects=killStats.effects+1
 return true
end

local function decorateKillingHit(hit,plate)
 plate=plate or (hit and hit.plate)
 if not plate or not db.showKillingBlow then return false end
 local killAt=killScheduled[plate]
 if not killAt or killDecorated[plate]==killAt then return false end
 local info=lastHits[plate]
 if not info or GetTime()-info.at>LAST_HIT_WINDOW then return false end
 if not spawnFinalNumberAt(info,plate) then return false end
 -- The last normal hit is replaced by the dedicated final-hit frame so the
 -- same amount is not drawn twice. Its own FontString remains pool-owned.
 if hit and hit.fs then hit.suppressed=true;hit.fs:Hide();releaseStatusLabel(hit) end
 killDecorated[plate]=killAt
 return true
end
-- UNIT_COMBAT('player', 'HEAL', ...) reports the HEAL RECEIVED, regardless of
-- who cast it. It must not be correlated with the outgoing-damage Smart log.
-- Prefer the personal nameplate while it is visible, then the player unit
-- frame, and finally a safe point around the on-screen player character.
local function playerHealAnchor()
 if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit)=='function' then
  local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,'player')
  if ok and plate then
   local visible=true
   if plate.IsShown then
    local shownOK,shown=pcall(plate.IsShown,plate)
    visible=shownOK and safeValue(shown) and shown==true
   end
   if visible then return plate end
  end
 end
 for _,name in ipairs({'ElvUF_Player','PlayerFrame'}) do
  local frame=_G[name]
  if frame then
   local visible=true
   if frame.IsShown then
    local ok,shown=pcall(frame.IsShown,frame)
    visible=ok and safeValue(shown) and shown==true
   end
   if visible then return frame end
  end
 end
 return UIParent
end
local function placePlayerHeal(fs,anchor,x,y)
 if anchor==UIParent then
  fs:SetPoint('CENTER',UIParent,'CENTER',x,y-95)
 else
  fs:SetPoint('CENTER',anchor,'TOP',x,y)
 end
end
local function startNumber(plate,amount,critical,preview,allowRemoved,isNotice,isHeal,isGlancing,blockKind,unverified,isXP)
 if not plate then return false end
 if not preview and (not db.enabled or (db.damageSource~='coverage' and db.damageSource~='all')) then return false end
 local removed=not isHeal and allowRemoved and recentForPlate(plate)
 -- Leave ordinary damage anchored on the Blizzard nameplate exactly as in
 -- 0.7.12. Only an already hidden/vanishing nameplate uses the overlay,
 -- after confirming it has a cached position. This branch must never require
 -- screen coordinates for ordinary hits on visible nameplates.
 local hiddenFinal=false
 if not isHeal and plate.IsShown and not removed then
  local ok,shown=pcall(plate.IsShown,plate)
  if not ok or not safeValue(shown) or shown~=true then
   if platePositions[plate] or rememberPosition(plate) then hiddenFinal=true
   else return false end
  end
 end
 local detached=(removed and true or false) or hiddenFinal
 local anchor
 if not detached and not isHeal and db.plateDisplayEnabled and plateDisplay then
  anchor=plateDisplay:Attach(plate)
  if anchor then plateRenderStats.anchored=plateRenderStats.anchored+1
  else plateRenderStats.fallback=plateRenderStats.fallback+1 end
 end
 local fs=table.remove(pool)
 if not fs then fs=UIParent:CreateFontString(nil,'OVERLAY') end
 fs:SetParent(isHeal and plate or detached and fxLayer or anchor or plate)
 fs:ClearAllPoints()
 local position=not isHeal and (removed and (removed.position or platePositions[plate]) or (hiddenFinal and platePositions[plate]) or rememberPosition(plate)) or nil
 local mode=db.animationStyle or 'arc'
 local offsetX=(isHeal and 0) or db[mode..(critical and 'CritX' or 'NormalX')] or 0
 local offsetY=(isHeal and 0) or db[mode..(critical and 'CritY' or 'NormalY')] or 0
 -- Initial placement must match the selected motion profile (no first-frame jump).
 local initialY=db.startY
 if db.animationStyle=='popup' then initialY=db.popupStartY
 elseif db.animationStyle=='float' then initialY=db.floatStartY
 elseif db.animationStyle=='bounce' then initialY=db.bounceStartY end
 if isHeal then placePlayerHeal(fs,plate,offsetX,initialY+offsetY)
 elseif detached and position then fs:SetPoint('CENTER',fxLayer,'BOTTOMLEFT',position.x+offsetX,position.y+initialY+offsetY)
 elseif anchor then fs:SetPoint('CENTER',anchor,'CENTER',offsetX,initialY+offsetY)
 else fs:SetPoint('CENTER',plate,'TOP',offsetX,initialY+offsetY) end
 local fontName=critical and db.critFont or db.font
 local baseSize=db.size*(critical and db.critScale or 1)
 setFont(fs,baseSize,fontName)
 if isXP then fs:SetTextColor(.72,.43,1) -- Violet XP; incoming healing stays green
 elseif isHeal then fs:SetTextColor(.30,1,.43)
 elseif isNotice=='MISS' then fs:SetTextColor(.78,.84,.91)
 elseif isNotice=='DODGE' then fs:SetTextColor(1,.77,.39)
 elseif isNotice=='PARRY' then fs:SetTextColor(.92,.94,.96)
 elseif isNotice=='BLOCK' then fs:SetTextColor(.67,.71,.77)
 elseif blockKind then fs:SetTextColor(.73,.77,.83)
 elseif isGlancing then fs:SetTextColor(.84,.87,.91)
 elseif critical then fs:SetTextColor(1,.86,.12)
 elseif unverified then fs:SetTextColor(.76,.84,.93)
 else fs:SetTextColor(1,1,1) end
 -- A secret amount is sent ONLY to the UI setter: no tostring, comparison or math.
 local ok=pcall(function() fs:SetText(amount) end)
 if not ok then fs:Hide();fs:SetParent(UIParent);pool[#pool+1]=fs;return false end
 -- A different direction can be selected for each animation profile.
 -- Only user settings (never secret combat values) are inspected here.
 local directionKey=({arc='direction',popup='popupDirection',float='floatDirection',bounce='bounceDirection'})[mode] or 'direction'
 local choice=db[directionKey] or 'alternate'
 directionIndex=directionIndex+1
 local dir
 if choice=='left' then dir=-1
 elseif choice=='right' then dir=1
 elseif choice=='random' then dir=(math.random(2)==1) and -1 or 1
 else dir=(directionIndex%2==0) and 1 or -1 end
 local verticalKey=({arc='verticalDirection',popup='popupVerticalDirection',float='floatVerticalDirection',bounce='bounceVerticalDirection'})[mode] or 'verticalDirection'
 local verticalChoice=db[verticalKey] or 'up'
 local vdir=1
 if verticalChoice=='down' then vdir=-1
 elseif verticalChoice=='alternate' then vdir=(directionIndex%2==0) and 1 or -1
 elseif verticalChoice=='random' then vdir=(math.random(2)==1) and 1 or -1 end
 local duration,startY,rise,arc,curve,fade=db.duration,db.startY,db.rise,db.arc,db.curve,db.fade
 local peak,intro,hold,drift,sway,decay,travel
 if mode=='popup' then
  duration,startY,rise,arc,curve,fade=db.popupDuration,db.popupStartY,db.popupRise,0,0,db.popupFade
  peak,intro,hold=db.popupPeak,db.popupIn/100,db.popupHold/100
  travel=db.popupTravel
 elseif mode=='float' then
  duration,startY,rise,arc,curve,fade=db.floatDuration,db.floatStartY,db.floatRise,0,0,db.floatFade
  drift,sway=db.floatDrift,db.floatSway
 elseif mode=='bounce' then
  duration,startY,rise,arc,curve,fade=db.bounceDuration,db.bounceStartY,db.bounceHeight,0,0,db.bounceFade
  peak,decay=db.bouncePeak,db.bounceDecay
  travel=db.bounceTravel
 else mode='arc' end
 fs:SetAlpha(1);fs:Show()
 local prefix,suffix
 if isHeal and not isXP then
  prefix=makeHealAffix(fs,'+',fontName,baseSize,'prefix')
  suffix=makeHealAffix(fs,'HP',fontName,baseSize,'suffix')
 end
 local hit={healPrefix=prefix,healSuffix=suffix,fs=fs,plate=plate,anchor=anchor,position=position,detached=detached,heal=isHeal,t=0,dir=dir,vdir=vdir,mode=mode,
  duration=duration,startY=startY,rise=rise,arc=arc,curve=curve,fade=fade,
  peak=peak,intro=intro,hold=hold,drift=drift,sway=sway,decay=decay,travel=travel,
  offsetX=offsetX,offsetY=offsetY,
  baseSize=baseSize,fontName=fontName,lastScale=1,xp=isXP}
 if not isNotice and not isHeal then
  if blockKind then hit.statusLabel=createStatusLabel(fs,fontName,baseSize,'BLOCKED')
  elseif isGlancing then hit.statusLabel=createStatusLabel(fs,fontName,baseSize,'GLANCING') end
 end
 active[#active+1]=hit
 -- A BLOCK event may report the amount BLOCKED, not damage landed. Do not
 -- promote that value to last-hit/Overkill; WOUND/DAMAGE with BLOCKED
 -- descriptor still reports real landed damage and remains eligible.
 if not preview and not isNotice and not isHeal and blockKind~="result" and not unverified then
  lastHits[plate]={hit=hit,at=GetTime(),position=position,amount=amount,critical=critical,
   startY=startY,offsetX=offsetX,offsetY=offsetY}
  -- The final UNIT_COMBAT may arrive after PARTY_KILL; the ribbon uses
  -- its own overlay layer and is not released with this numeric hit.
  local killAt=killScheduled[plate]
  -- Only a personally confirmed PARTY_KILL is decorated immediately.
  -- UNIT_DIED and nameplate removal are finalized after Smart matching.
  if killAt and confirmedPersonalKills[plate] and GetTime()-killAt<=1.10 then decorateKillingHit(hit,plate) end
 end
 return true
end
-- PLAYER_XP_UPDATE is sourced from the player's own XP bar, not UNIT_COMBAT.
-- Skip the initial sample and any unreadable/secret API values.
local function snapshotXP()
 if type(UnitXP)~='function' or type(UnitXPMax)~='function' then return nil end
 local ok,now,maximum=pcall(function() return UnitXP('player'),UnitXPMax('player') end)
 if not ok or not safeValue(now) or not safeValue(maximum)
    or type(now)~='number' or type(maximum)~='number'
    or maximum<=0 or now<0 then return nil end
 return now,maximum
end
local function showXPUpdate()
 local now,maximum=snapshotXP()
 if not now then playerTextStats.ignored=playerTextStats.ignored+1;return end
 local before,beforeMax=xpPrevious,xpPreviousMax
 xpPrevious,xpPreviousMax=now,maximum
 if before==nil or beforeMax==nil then return end
 local gained=now-before
 if gained<0 and beforeMax>before then
  -- The XP bar wrapped after a level-up.
  gained=beforeMax-before+now
 end
 if gained<=0 or gained>100000000 then return end
 if not db or not db.enabled or db.damageSource~='coverage' then return end
 local anchor=playerDisplay and playerDisplay:Attach('xp')
 if not anchor then anchor=playerHealAnchor() end
 local ok,shown=pcall(startNumber,anchor,'+'..math.floor(gained+.5)..' XP',false,false,false,nil,true,nil,nil,nil,true)
 if ok and shown then playerTextStats.xp=playerTextStats.xp+1
 else playerTextStats.ignored=playerTextStats.ignored+1 end
end
-- The client passes a display-only COMBAT_LOG_MESSAGE from Blizzard's selected
-- combat log filter. The message contents are never decoded or inspected if secret.
local function onFilteredCombatMessage(message,order)
 if not db or not db.enabled or db.combatLogEnabled==false or db.damageSource~='coverage' then return end
 local oldest=Enum and Enum.CombatLogMessageOrder and Enum.CombatLogMessageOrder.Oldest
 if oldest~=nil and not (issecretvalue and issecretvalue(order)) and order==oldest then
  smartStats.oldest=smartStats.oldest+1;return
 end
 smartStats.messages=smartStats.messages+1
 local hidden=(issecretvalue and issecretvalue(message)) or false
 if not hidden then
  if type(message)~='string' then hidden=true
  else hidden=(string.find(message,'|K',1,true)~=nil) end
 end
 if not hidden then smartStats.readable=smartStats.readable+1;return end
 smartStats.hidden=smartStats.hidden+1
 smartFlow=true
 smartCredits[#smartCredits+1]={at=GetTime()}
 if #smartCredits>60 then table.remove(smartCredits,1);smartStats.expired=smartStats.expired+1 end
end
local function queueSmartHit(unit,plate,amount,critical,notice,isGlancing,blockKind,kind,action)
 -- Filtering solely by timing can accidentally pair other players' pets with
 -- our credits. The victim must be our target (or our OWN pet's target).
 local permitted,petCandidate=isPersonalTarget(unit,plate)
 local coverageEligible=false
 if db.damageSource=='coverage' then
  coverageEligible=coverageOwnTarget(unit,plate)
  if coverageEligible and not permitted then permitted=true end
 end
 if not permitted then smartStats.discarded=smartStats.discarded+1;return end
 smartStats.queued=smartStats.queued+1
 -- Store protected damage amounts verbatim: SetText is their only consumer.
 if petCandidate then petStats.candidates=petStats.candidates+1 end
 smartPending[#smartPending+1]={at=GetTime(),unit=unit,plate=plate,amount=amount,critical=critical,notice=notice,isGlancing=isGlancing,blockKind=blockKind,petCandidate=petCandidate,
  coverageEligible=coverageEligible,coverageKind=kind or 'unknown',coverageAlias=(unit=='target'),coverageAction=action}
 if #smartPending>60 then table.remove(smartPending,1);smartStats.discarded=smartStats.discarded+1 end
end
local function processSmartHits()
 if not db or not db.enabled or db.damageSource~='coverage' then return end
 local now=GetTime()
 local i=1
 while i<=#smartCredits do
  local credit=smartCredits[i]
  if now-credit.at>=SMART_RESOLVE then
   local best,bestScore
   for j,hit in ipairs(smartPending) do
    local delta=math.abs(credit.at-hit.at)
    if delta<=SMART_WINDOW then
     local score=delta
     if UnitIsUnit then
      local ok,same=pcall(UnitIsUnit,hit.unit,'target')
      if ok and same then score=score-.015 end
     end
     if not bestScore or score<bestScore then best,bestScore=j,score end
    end
   end
   if best then
    local hit=table.remove(smartPending,best)
    table.remove(smartCredits,i)
    local late=recentForPlate(hit.plate)~=nil
    local ok,shown=pcall(startNumber,hit.plate,hit.amount,hit.critical,false,late,hit.notice,false,hit.isGlancing,hit.blockKind)
    if ok and shown then
     if db.damageSource=='coverage' then coverageStats.credited=coverageStats.credited+1;coverageRecord(hit.coverageKind) end
     smartStats.matched=smartStats.matched+1
     if hit.petCandidate then petStats.matched=petStats.matched+1 end
     if not hit.notice and hit.blockKind~="result" then
      lastShown[hit.plate]=now
      lastPersonalPlate,lastPersonalAt=hit.plate,now
      if late then killStats.late=killStats.late+1 end
     end
    else smartStats.failed=smartStats.failed+1 end
   elseif now-credit.at>SMART_EXPIRE then
    table.remove(smartCredits,i);smartStats.expired=smartStats.expired+1
   else i=i+1 end
  else i=i+1 end
 end
 for j=#smartPending,1,-1 do
  local hit=smartPending[j]
  if now-hit.at>SMART_EXPIRE then
   table.remove(smartPending,j)
   -- Best-effort display of repeated DoT ticks and unmatched hits on targets
   -- that the player cast/swang at. The victim-only event cannot prove who
   -- attacked; never do this in a party/raid.
   local allowed=db.damageSource=='coverage' and hit.coverageEligible and coverageIsSolo()
   if allowed and hit.coverageAlias and coverageAliasDuplicate(hit.plate,hit.coverageAction,hit.at) then
    allowed=false;coverageStats.aliasSkipped=coverageStats.aliasSkipped+1
   end
   if allowed then
    local late=recentForPlate(hit.plate)~=nil
    local ok,shown=pcall(startNumber,hit.plate,hit.amount,hit.critical,false,late,hit.notice,false,hit.isGlancing,hit.blockKind,true)
    if ok and shown then
     coverageStats.soloFallback=coverageStats.soloFallback+1
     coverageRecord(hit.coverageKind)
     -- Victim-only solo fallback is not evidence of a personal killing blow.
    else smartStats.failed=smartStats.failed+1 end
   else
    smartStats.discarded=smartStats.discarded+1
    if db.damageSource=='coverage' then coverageStats.unverified=coverageStats.unverified+1 end
   end
  end
 end
end
-- Prefer an exact victim match; NEVER compare a PARTY_KILL attacker GUID
-- to the enemy plate GUID (the event has *two* separate GUID arguments).
local function plateByVictimGUID(guid)
 if not guid then return nil end
 for unit,plate in pairs(plates) do
  local known=safeGUID(unit) or plateGuids[unit]
  if known and known==guid then return plate end
 end
 for _,entry in pairs(recentPlates) do
  if entry.guid and entry.guid==guid and GetTime()-entry.at<DEATH_GRACE then return entry.plate end
 end
end
local function plateCompatibleWithVictim(plate,guid)
 if not plate then return false end
 if not guid then return true end
 for unit,current in pairs(plates) do
  if current==plate then
   local known=safeGUID(unit) or plateGuids[unit]
   if known then return known==guid end
  end
 end
 local entry=recentForPlate(plate)
 return entry and (not entry.guid or entry.guid==guid) or false
end
local function plateForKill(guid)
 -- First try the actual victim GUID on visible and recently removed plates.
 local exact=plateByVictimGUID(guid)
 if exact then return exact end
 -- PARTY_KILL often precedes NAME_PLATE_UNIT_REMOVED. Prefer the current
 -- target when a personal Smart damage was actually matched recently.
 local best,bestScore,now=nil,nil,GetTime()
 for unit,plate in pairs(plates) do
  local stamp=lastShown[plate]
  if stamp and now-stamp<=.75 then
   local known=safeGUID(unit) or plateGuids[unit]
   if not guid or not known or known==guid then
    local score=now-stamp
    if isUnitTarget(unit) then score=score-1 end
    if not bestScore or score<bestScore then best,bestScore=plate,score end
   end
  end
 end
 if best then return best end
 if lastPersonalPlate and now-(lastPersonalAt or 0)<1.35 and plateCompatibleWithVictim(lastPersonalPlate,guid) then
  killFallbackStats.personal=killFallbackStats.personal+1
  return lastPersonalPlate
 end
 local entry=lastRemoved(guid,true)
 if entry and now-entry.at<=1.10 and plateCompatibleWithVictim(entry.plate,guid) then return entry.plate end
 if lastTargetPlate and now-(lastTargetAt or 0)<1.10 and plateCompatibleWithVictim(lastTargetPlate,guid) then
  killFallbackStats.target=killFallbackStats.target+1
  return lastTargetPlate
 end
end
local function schedulePersonalKill(plate,now)
 if not plate or (foreignKillPlates[plate] and now-foreignKillPlates[plate]<DEATH_GRACE) then return false end
 if killScheduled[plate] and now-killScheduled[plate]<1.10 then return true end
 killScheduled[plate]=now
 pendingKills[#pendingKills+1]={plate=plate,at=now}
 return true
end
local function notePersonalKill(attackerGUID,victimGUID)
 if not db or not db.enabled or not db.showKillingBlow or db.damageSource=='player' then return end
 -- PARTY_KILL(attackerGUID, targetGUID) also fires for other party members.
 -- Only promote our own (or our pet's) killing blows when identity is readable.
 if safeValue(attackerGUID) and type(attackerGUID)=='string' then
  local playerGUID=safeGUID('player')
  local petGUID=safeGUID('pet')
  if (playerGUID or petGUID) and attackerGUID~=playerGUID and attackerGUID~=petGUID then
   -- A party member's kill must not be relabelled as our killing blow by
   -- the later UNIT_DIED / nameplate-removal fallback.
   if safeValue(victimGUID) and type(victimGUID)=='string' then
    local foreignPlate=plateByVictimGUID(victimGUID)
    if foreignPlate then
     foreignKillPlates[foreignPlate]=GetTime()
     for i=#pendingKills,1,-1 do
      if pendingKills[i].plate==foreignPlate then table.remove(pendingKills,i) end
     end
     killScheduled[foreignPlate]=nil
     confirmedPersonalKills[foreignPlate]=nil
    end
   end
   return
  end
 end
 killStats.signals=killStats.signals+1
 if not safeValue(victimGUID) or type(victimGUID)~='string' then victimGUID=nil end
 local now=GetTime()
 local plate=plateForKill(victimGUID)
 if not plate then
  -- PARTY_KILL can be emitted *before* a dead mob's nameplate is removed,
  -- while its unit token and GUID are already invalid. Resolve it later.
  unresolvedKillSignals[#unresolvedKillSignals+1]={guid=victimGUID,at=now}
  return
 end
 confirmedPersonalKills[plate]=now
 schedulePersonalKill(plate,now)
end
-- UNIT_DIED is available on Forever even though the old CLEU is not.
-- When PARTY_KILL is absent, a known dead GUID plus our recent displayed hit
-- is a best-effort *final-hit visual*, not proof of true overkill excess.
local function noteUnitDeath(guid)
 if not db or not db.enabled or not db.showKillingBlow or db.damageSource=='player' then return end
 if not safeValue(guid) or type(guid)~='string' then return end
 local plate=plateByVictimGUID(guid)
 if not plate then return end
 local info=lastHits[plate]
 local now=GetTime()
 -- Queue the confirmed death even if its Smart damage is still waiting for
 -- matching. processKillingBlows only displays the number if a hit arrives.
 if not foreignKillPlates[plate] and (not info or now-info.at<=LAST_HIT_WINDOW) then
  schedulePersonalKill(plate,now)
 end
end
local function resolvePersonalKillSignals()
 local now=GetTime()
 for i=#unresolvedKillSignals,1,-1 do
  local signal=unresolvedKillSignals[i]
  local plate=plateForKill(signal.guid)
  if not plate then
   -- With an unreadable victim GUID, the only safe-ish fallback is exactly
   -- ONE freshly removed nameplate around the confirmed personal kill.
   local count,candidate=0,nil
   for _,entry in pairs(recentPlates) do
    if now-entry.at<.8 and entry.at-signal.at<=.75 and entry.at-signal.at>=-.20
      and (not signal.guid or not entry.guid or signal.guid==entry.guid) then
     count=count+1;candidate=entry.plate
    end
   end
   if count==1 then plate=candidate end
  end
  if plate then
   confirmedPersonalKills[plate]=now
   schedulePersonalKill(plate,now)
   killStats.lateSignals=killStats.lateSignals+1
   table.remove(unresolvedKillSignals,i)
  elseif now-signal.at>1.10 then
   -- A personal PARTY_KILL was delivered but the dying nameplate had
   -- no readable GUID/target/coordinates. Never silently discard its FX.
   -- Screen fallback is deliberately NOT advertised as being on the corpse.
   -- No associated damage amount: do not show made-up final numbers.
   killStats.labels=killStats.labels+1
   table.remove(unresolvedKillSignals,i)
  end
 end
end
local function inferRecentlyRemovedKills()
 if not db or not db.enabled or not db.showKillingBlow or db.damageSource~='coverage' then return end
 local now=GetTime()
 for _,entry in pairs(recentPlates) do
  local plate=entry.plate
  local last=lastShown[plate]
  -- A disappearing nameplate is NOT proof of death. Only infer a visual
  -- effect if a *matched personal* hit was displayed within a very short
  -- interval of the disappearance. Wait for late Smart pairing to settle.
  if last and now-entry.at>=.29 and now-entry.at<=.80
     and math.abs(last-entry.at)<=.38
     and not inferredAt[plate] and not killScheduled[plate]
     and not foreignKillPlates[plate] then
   local position=entry.position or platePositions[plate]
   if position and safeValue(position.x) and safeValue(position.y) then
    killScheduled[plate]=now
    inferredAt[plate]=now
    pendingKills[#pendingKills+1]={plate=plate,at=now}
    killStats.inferred=killStats.inferred+1
   end
  end
 end
end
local function processKillingBlows()
 local now=GetTime()
 for i=#pendingKills,1,-1 do
  local kill=pendingKills[i]
  -- Allow the last UNIT_COMBAT message and the Smart credit to pair first.
  if now-kill.at>=KILL_RESOLVE_DELAY then
   table.remove(pendingKills,i)
   local info=lastHits[kill.plate]
   if info and now-info.at<=LAST_HIT_WINDOW then
    if killDecorated[kill.plate]==killScheduled[kill.plate] then
     -- Smart amount arrived AFTER the kill and was already promoted.
     killStats.numeric=killStats.numeric+1
    else
     local running
     for _,hit in ipairs(active) do
      if hit==info.hit then running=hit;break end
     end
     if decorateKillingHit(running,kill.plate) then
      killStats.numeric=killStats.numeric+1
     else killStats.unmatched=killStats.unmatched+1 end
    end
   else
    -- A kill notification does not contain the raw damage amount.
    -- Without a matched personal hit, we must not fabricate a number.
    killStats.labels=killStats.labels+1
   end
  end
 end
end

engine:SetScript('OnUpdate',function(_,elapsed)
 -- Cache last-known onscreen positions before Blizzard recycles or hides
 -- nameplates. This keeps final effects visually fixed at the death location.
 plateCacheTick=plateCacheTick+elapsed
 if plateCacheTick>=.08 then
  plateCacheTick=0
  for unit,plate in pairs(plates) do
   local shown=true
   if plate.IsShown then
    local ok,result=pcall(plate.IsShown,plate)
    shown=ok and safeValue(result) and result==true
   end
   if shown then
    rememberPosition(plate)
    if isUnitTarget(unit) then lastTargetPlate,lastTargetAt=plate,GetTime() end
   end
  end
 end
 for i=#active,1,-1 do
  local a=active[i]
  a.t=a.t+elapsed
  local p=math.min(1,a.t/math.max(.1,a.duration))
  if p>=1 then
   releaseStatusLabel(a)
   releaseHealAffixes(a)
   a.fs:Hide();a.fs:SetParent(UIParent);pool[#pool+1]=a.fs;table.remove(active,i)
  elseif not a.suppressed then
   if not a.detached and not a.heal then
    local shown=true
    if a.plate.IsShown then
     local ok,value=pcall(a.plate.IsShown,a.plate)
     shown=ok and safeValue(value) and value==true
    end
    if not shown then
     a.position=platePositions[a.plate] or a.position
     a.detached=true
     a.anchor=nil
     a.fs:SetParent(fxLayer)
     if not a.position then
      a.suppressed=true
      a.fs:Hide()
      releaseStatusLabel(a)
     end
    elseif not a.anchor then
     -- Independent anchors move with the plate: no per-frame coordinate read.
     a.position=rememberPosition(a.plate) or a.position
    end
   end
   if not a.suppressed then
   local x,y,scale=motionAt(a,p)
   -- Popup and bounce animate text size; normal hits don't update fonts per frame.
   if scale and math.abs(scale-(a.lastScale or 1))>=.035 then
    setFont(a.fs,math.max(5,a.baseSize*scale),a.fontName)
    if a.statusLabel then setFont(a.statusLabel,math.max(9,a.baseSize*scale*.40),a.fontName) end
    if a.healPrefix then setFont(a.healPrefix,math.max(10,a.baseSize*scale*.8),a.fontName) end
    if a.healSuffix then setFont(a.healSuffix,math.max(10,a.baseSize*scale*.8),a.fontName) end
    a.lastScale=scale
   end
   local alpha=fadeAt(a,p)
   a.fs:SetAlpha(alpha)
   if a.statusLabel then a.statusLabel:SetAlpha(alpha) end
   if a.healPrefix then a.healPrefix:SetAlpha(alpha) end
   if a.healSuffix then a.healSuffix:SetAlpha(alpha) end
   a.fs:ClearAllPoints()
   if a.heal then
    placePlayerHeal(a.fs,a.plate,x,y)
   elseif a.detached and a.position then
    a.fs:SetPoint('CENTER',fxLayer,'BOTTOMLEFT',a.position.x+x,a.position.y+y)
   else
    anchorNumber(a.fs,a,x,y)
   end
   end
  end
 end
 -- Each final-hit effect is drawn in its own frame on the enemy nameplate.
 -- When that plate vanishes, retain the *last known plate position* only.
 for i=#overkills,1,-1 do
  local fx=overkills[i]
  fx.t=fx.t+elapsed
  local p=math.min(1,fx.t/math.max(.1,fx.duration))
  if fx.expired or p>=1 then
   releaseOverkill(fx)
   table.remove(overkills,i)
  else
   if not fx.frozen and fx.plate.IsShown then
    local ok,shown=pcall(fx.plate.IsShown,fx.plate)
    if not ok or not safeValue(shown) or not shown then
     freezeOverkillsForPlate(fx.plate,platePositions[fx.plate] or fx.position)
    end
   end
   if fx.expired then
    releaseOverkill(fx)
    table.remove(overkills,i)
   else
    local alpha=1
    if p>.62 then alpha=1-(p-.62)/.38 end
    fx.frame:SetAlpha(alpha)
    fx.rise=33*p+12*4*p*(1-p)
    fx.shakeX,fx.shakeY=overkillShakeAt(fx.t,db.overkillShakeIntensity)
    local ok,placed=pcall(placeOverkill,fx,fx.rise)
    if not ok or not placed then
     releaseOverkill(fx)
     table.remove(overkills,i)
     killFallbackStats.noPosition=killFallbackStats.noPosition+1
    end
   end
  end
 end
 if db and db.enabled and (db.damageSource=='coverage' or db.damageSource=='all') then
  if db.damageSource=='coverage' then processSmartHits() end
  resolvePersonalKillSignals()
  -- Preserve original kill attribution; Coverage uses its own verification rules.
  processKillingBlows()
  for unit,entry in pairs(recentPlates) do
   if GetTime()-entry.at>DEATH_GRACE then recentPlates[unit]=nil end
  end
  smartTick=smartTick+elapsed
  if db.damageSource=='coverage' and smartTick>3 then smartTick=0;enableFilteredLog() end
 end
end)
-- UI helpers. Compact charcoal/orange typographic style inspired by
-- clean WoW addon suites. All UI font faces remain user-configurable.
-- Settings color palettes apply only to the addon configuration window.
-- Combat damage colors and the independent Overkill FX never use this palette.
local uiButtons,uiAccentTexts,uiAccentTextures={},{},{}
local UI_COLOR_STYLES={
 ember={name='Ember Orange',accent={1,.59,.30},soft={1,.77,.54},window={.067,.078,.094},sidebar={.080,.092,.113},button={.135,.15,.19},hover={.85,.42,.15}},
 glacier={name='Glacier Blue',accent={.34,.72,1},soft={.69,.87,1},window={.063,.080,.104},sidebar={.073,.101,.132},button={.116,.163,.206},hover={.20,.53,.82}},
 emerald={name='Emerald',accent={.33,.87,.62},soft={.68,1,.84},window={.057,.080,.073},sidebar={.070,.103,.092},button={.112,.160,.139},hover={.17,.64,.39}},
 amethyst={name='Amethyst',accent={.78,.58,1},soft={.89,.77,1},window={.081,.072,.107},sidebar={.104,.084,.134},button={.164,.137,.207},hover={.55,.31,.80}},
 graphite={name='Graphite',accent={.84,.87,.92},soft={1,1,1},window={.073,.079,.091},sidebar={.091,.098,.111},button={.155,.164,.181},hover={.60,.66,.74}},
}
local function currentUISkin()
 return UI_COLOR_STYLES[db and db.uiColorStyle] or UI_COLOR_STYLES.ember
end
local function tintTexture(tx,c,a)
 if not tx or not c then return end
 if tx.SetColorTexture then tx:SetColorTexture(c[1],c[2],c[3],a or 1)
 else tx:SetTexture('Interface\\Buttons\\WHITE8X8');tx:SetVertexColor(c[1],c[2],c[3],a or 1) end
end
local function trackUI(fs,size)
 setFont(fs,size,db.uiFont or defaultUIFont)
 uiTextEntries[#uiTextEntries+1]={fs=fs,size=size}
end
local function refreshUIFont()
 for _,item in ipairs(uiTextEntries) do
  setFont(item.fs,item.size,db.uiFont or defaultUIFont)
 end
end

local function label(parent,str,x,y,size,r,g,b)
 local fs=parent:CreateFontString(nil,'OVERLAY')
 fs:SetPoint('TOPLEFT',x,y);trackUI(fs,size)
 fs:SetText(str);fs:SetTextColor(r or .91,g or .92,b or .94)
 return fs
end
local function button(parent,caption,x,y,width,height,click,accent)
 local b=CreateFrame('Button',nil,parent)
 b:SetPoint('TOPLEFT',x,y);b:SetSize(width,height or 30)
 -- Full-width option rows stretch with their active tab when the window grows.
 if width==499 and x==220 and parent._shaaenOptionPanel then
  b:SetPoint('TOPRIGHT',parent,'TOPRIGHT',-36,y)
 end
 local background=colorTexture(b,accent and .24 or .135,accent and .17 or .15,accent and .14 or .19,1)
 local stripe=fixedTexture(b,'TOPLEFT',0,0,2,height or 30,accent and .98 or .29,accent and .52 or .32,accent and .27 or .38,1)
 local hover=b:CreateTexture(nil,'BACKGROUND',nil,1)
 hover:SetAllPoints(b);tintTexture(hover,currentUISkin().hover)
 hover:SetAlpha(0)
 local function animateHover(self,target)
  self._hoverTarget=target
  self:SetScript('OnUpdate',function(frame,elapsed)
   local old=hover:GetAlpha()
   local nextAlpha=old+(frame._hoverTarget-old)*math.min(1,elapsed*16)
   if math.abs(nextAlpha-frame._hoverTarget)<.008 then
    nextAlpha=frame._hoverTarget;frame:SetScript('OnUpdate',nil)
   end
   hover:SetAlpha(nextAlpha)
  end)
 end
 b:SetScript('OnEnter',function(self) animateHover(self,.27) end)
 b:SetScript('OnLeave',function(self) animateHover(self,0) end)
 b._skinStripe=stripe;b._skinHover=hover;b._skinAccent=accent
 b._skinBackground=background
 uiButtons[#uiButtons+1]=b
 local t=b:CreateFontString(nil,'OVERLAY')
 t:SetPoint('CENTER');trackUI(t,12);t:SetText(caption)
 t:SetTextColor(1,accent and .81 or .91,accent and .62 or .95)
 b.caption=t;b.stripe=stripe
 b:SetScript('OnClick',click or function() end)
 return b
end
-- Switches use textures rather than decorative bullet glyphs. The whole row is clickable.
local function toggleRow(parent,caption,y,onClick)
 local row=button(parent,caption,220,y,499,31,onClick)
 row.caption:ClearAllPoints()
 row.caption:SetPoint('LEFT',row,'LEFT',14,0)
 row.caption:SetJustifyH('LEFT')
 local track=CreateFrame('Frame',nil,row)
 track:SetSize(57,23);track:SetPoint('RIGHT',row,'RIGHT',-10,0)
 local bg=track:CreateTexture(nil,'ARTWORK')
 bg:SetAllPoints(track)
 local knob=track:CreateTexture(nil,'OVERLAY')
 knob:SetSize(17,17)
 local onText=track:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
 onText:SetPoint('CENTER',track,'CENTER',0,0)
 onText:SetTextColor(1,1,1)
 function row:RefreshSwitch(on)
  local skin=currentUISkin()
  tintTexture(bg,on and skin.accent or {.29,.33,.40},1)
  tintTexture(knob,{.96,.97,.98},1)
  knob:ClearAllPoints()
  knob:SetPoint(on and 'RIGHT' or 'LEFT',track,on and 'RIGHT' or 'LEFT',on and -3 or 3,0)
  onText:SetText(on and 'ON' or 'OFF')
  onText:ClearAllPoints()
  onText:SetPoint('CENTER',track,'CENTER',on and -9 or 9,0)
 end
 row._switchTrack=track
 return row
end
local function header(parent,title,subtitle,settingsPage)
 local shift=settingsPage and 44 or 0
 label(parent,title,215,-90-shift,24,.98,.98,.99)
 label(parent,subtitle,215,-125-shift,12,.61,.66,.72)
 local rule=fixedTexture(parent,'TOPLEFT',215,-148-shift,505,1,.25,.28,.33,.85)
 rule:SetPoint('TOPRIGHT',parent,'TOPRIGHT',-35,-148-shift)
 local accentRule=fixedTexture(parent,'TOPLEFT',215,-148-shift,60,2,.94,.50,.25,1)
 uiAccentTextures[#uiAccentTextures+1]=accentRule
end
local function section(parent,title,y)
 local fs=label(parent,title,220,y,12,1,.62,.35)
 uiAccentTexts[#uiAccentTexts+1]=fs
end
local function valueSlider(parent,key,title,y,formatSuffix)
 local r=ranges[key]
 label(parent,title,222,y,13,.89,.92,.95)
 local value=label(parent,'',671,y,13,1,.72,.42)
 uiAccentTexts[#uiAccentTexts+1]=value
 value:ClearAllPoints();value:SetPoint('TOPRIGHT',parent,'TOPRIGHT',-32,y)
 value:SetWidth(52);value:SetJustifyH('RIGHT')
 local slider=CreateFrame('Slider',nil,parent)
 slider:SetOrientation('HORIZONTAL')
 slider:SetPoint('TOPLEFT',420,y-4);slider:SetSize(236,16)
 slider:SetPoint('TOPRIGHT',parent,'TOPRIGHT',-100,y-4)
 slider:SetMinMaxValues(r[1],r[2]);slider:SetValueStep(r[3])
 if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
 local track=slider:CreateTexture(nil,'BACKGROUND')
 track:SetPoint('LEFT',slider,'LEFT',0,0);track:SetPoint('RIGHT',slider,'RIGHT',0,0)
 track:SetHeight(4)
 if track.SetColorTexture then track:SetColorTexture(.29,.32,.38,1)
 else track:SetTexture('Interface\\Buttons\\WHITE8X8');track:SetVertexColor(.29,.32,.38,1) end
 slider:SetThumbTexture('Interface\\Buttons\\UI-SliderBar-Button-Horizontal')
 local thumb=slider:GetThumbTexture()
 if thumb then thumb:SetSize(18,21) end
 local function show(num)
  local v=math.floor((num/r[3])+.5)*r[3]
  v=math.max(r[1],math.min(r[2],v))
  db[key]=math.floor(v*1000+.5)/1000
  value:SetText(string.format('%.'..r[4]..'f',db[key])..(formatSuffix or ''))
 end
 slider:SetScript('OnValueChanged',function(_,n) show(n) end)
 slider:SetValue(db[key]);show(db[key])
 return slider
end
local function createWindow()
 if window then return window end
 uiTextEntries={};uiButtons={};uiAccentTexts={};uiAccentTextures={}
 local w=CreateFrame('Frame',nil,UIParent)
 -- Cache only after the full UI has been constructed successfully.
 -- Reserve space for a persistent bottom action bar on every tab.
 local minWidth,minHeight,maxWidth,maxHeight=755,760,1100,940
 local function clampSize(n,minimum,maximum)
  if type(n)~='number' or n~=n then return minimum end
  return math.max(minimum,math.min(maximum,n))
 end
 w:SetSize(clampSize(db.windowWidth,minWidth,maxWidth),clampSize(db.windowHeight,minHeight,maxHeight))
 w:SetScale((db.windowScale or 100)/100)
 w:SetAlpha((db.windowOpacity or 100)/100)
 w:SetPoint('CENTER',UIParent,'CENTER',
  type(db.windowX)=='number' and db.windowX or 0,
  type(db.windowY)=='number' and db.windowY or 0)
 w:SetFrameStrata('DIALOG')
 w:EnableMouse(true);w:SetMovable(true);w:SetResizable(true)
 if w.SetResizeBounds then w:SetResizeBounds(minWidth,minHeight,maxWidth,maxHeight)
 else
  if w.SetMinResize then w:SetMinResize(minWidth,minHeight) end
  if w.SetMaxResize then w:SetMaxResize(maxWidth,maxHeight) end
 end
 if w.SetClampedToScreen then w:SetClampedToScreen(true) end
 local function saveWindowLayout()
  db.windowWidth=math.floor(w:GetWidth()+.5)
  db.windowHeight=math.floor(w:GetHeight()+.5)
  local x,y=w:GetCenter()
  local uiX,uiY=UIParent:GetCenter()
  if type(x)=='number' and type(y)=='number' and type(uiX)=='number' and type(uiY)=='number' then
   db.windowX=x-uiX;db.windowY=y-uiY
  end
 end
 w:RegisterForDrag('LeftButton')
 w:SetScript('OnDragStart',function(self) self:StartMoving() end)
 w:SetScript('OnDragStop',function(self) self:StopMovingOrSizing();saveWindowLayout() end)
 -- Dynamic controls register their own lightweight layout functions. No OnUpdate
 -- is needed: layout is recalculated only when the user resizes the window.
 local responsiveLayouts={}
 local function addResponsive(fn) responsiveLayouts[#responsiveLayouts+1]=fn end
 local function layoutTabs()
  local extra=math.max(0,(w:GetWidth() or minWidth)-minWidth)
  for _,fn in ipairs(responsiveLayouts) do fn(extra) end
 end
 w:SetScript('OnSizeChanged',function() layoutTabs() end)
 local windowBG=colorTexture(w,.067,.078,.094,.99)
 -- Stretch decorative panels with the window; controls retain safe fixed positions.
 local topEdge=fixedTexture(w,'TOPLEFT',0,0,755,3,.93,.48,.24,1)
 uiAccentTextures[#uiAccentTextures+1]=topEdge
 topEdge:ClearAllPoints();topEdge:SetPoint('TOPLEFT',w,'TOPLEFT');topEdge:SetPoint('TOPRIGHT',w,'TOPRIGHT')
 local topDivider=fixedTexture(w,'TOPLEFT',0,-68,755,1,.20,.24,.29,1)
 topDivider:ClearAllPoints();topDivider:SetPoint('TOPLEFT',w,'TOPLEFT',0,-68)
 topDivider:SetPoint('TOPRIGHT',w,'TOPRIGHT',0,-68)
 local sidebar=fixedTexture(w,'TOPLEFT',0,-69,191,645,.080,.092,.113,.95)
 sidebar:ClearAllPoints();sidebar:SetPoint('TOPLEFT',w,'TOPLEFT',0,-69)
 sidebar:SetPoint('BOTTOMLEFT',w,'BOTTOMLEFT',0,0)
 local resizeGrip=CreateFrame('Button',nil,w)
 resizeGrip:SetSize(24,24);resizeGrip:SetPoint('BOTTOMRIGHT',w,'BOTTOMRIGHT',-2,2)
 if resizeGrip.SetFrameLevel and w.GetFrameLevel then resizeGrip:SetFrameLevel(w:GetFrameLevel()+30) end
 resizeGrip:EnableMouse(true);resizeGrip:RegisterForDrag('LeftButton')
 -- The invisible 24px corner handle remains usable without ornamental dots.
 resizeGrip:SetScript('OnDragStart',function(self)
  if not (InCombatLockdown and InCombatLockdown()) then self:GetParent():StartSizing('BOTTOMRIGHT') end
 end)
 resizeGrip:SetScript('OnDragStop',function(self)
  self:GetParent():StopMovingOrSizing()
  saveWindowLayout()
 end)
 -- Reset to a normal window after clicking the resizing handle twice.
 resizeGrip:SetScript('OnDoubleClick',function()
  w:SetSize(minWidth,minHeight)
  saveWindowLayout()
 end)
 -- NL monogram rendered with native textures/font strings (no external assets).
 local emblem=CreateFrame('Frame',nil,w)
 emblem:SetPoint('TOPLEFT',17,-15);emblem:SetSize(35,36)
 colorTexture(emblem,.14,.16,.20,1)
 local emblemRule=fixedTexture(emblem,'TOPLEFT',0,0,35,2,.98,.54,.28,1)
 uiAccentTextures[#uiAccentTextures+1]=emblemRule
 local initials=emblem:CreateFontString(nil,'OVERLAY')
 uiAccentTexts[#uiAccentTexts+1]=initials
 initials:SetPoint('CENTER',0,-1);trackUI(initials,19)
 initials:SetText('NL');initials:SetTextColor(1,.72,.43)
 label(w,'SHAAEN',63,-12,23,.96,.96,.97)
 local fctTitle=label(w,'FCT',164,-12,23,1,.58,.27)
 uiAccentTexts[#uiAccentTexts+1]=fctTitle
 label(w,'FLOATING COMBAT TEXT',64,-43,10,.61,.66,.73)
 -- Versions are displayed in the sidebar footer, not in the top title bar.
 -- Window actions live in the bottom-right footer, clear of the resize grip.
 local sidebarDivider=fixedTexture(w,'TOPLEFT',191,-69,1,645,.25,.27,.33,1)
 sidebarDivider:ClearAllPoints();sidebarDivider:SetPoint('TOPLEFT',w,'TOPLEFT',191,-69)
 sidebarDivider:SetPoint('BOTTOMLEFT',w,'BOTTOMLEFT',191,0)
 -- Main navigation keeps Settings, Animation, Help and About separate.
 -- Settings contains General, Style and Fonts sub-tabs that share this window.
 local tabs,tabButtons,settingsButtons={}, {}, {}
 local fontPopups={}
 local function addTab(key)
  local p=CreateFrame('Frame',nil,w)
  p:SetAllPoints(w);p:Hide();tabs[key]=p
  p._shaaenOptionPanel=true
  return p
 end
 local general=addTab('general')
 local stylePane=addTab('style')
 local typeface=addTab('fonts')
 local animation=addTab('animation')
 local about=addTab('about')
 local help=addTab('help')
 local refreshGeneral,refreshFonts,refreshStyle,animationPreview
 local settingsBar=CreateFrame('Frame',nil,w)
 settingsBar:SetPoint('TOPLEFT',w,'TOPLEFT',213,-78)
 settingsBar:SetPoint('TOPRIGHT',w,'TOPRIGHT',-35,-78)
 settingsBar:SetHeight(42)
 if settingsBar.SetFrameLevel and w.GetFrameLevel then
  settingsBar:SetFrameLevel(w:GetFrameLevel()+8)
 end
 local mainPage='settings'
 local function markTabs()
  local skin=currentUISkin()
  local chosen=(mainPage=='settings') and (db.settingsSection or 'general') or mainPage
  for key,p in pairs(tabs) do if key==chosen then p:Show() else p:Hide() end end
  if mainPage=='settings' then settingsBar:Show() else settingsBar:Hide() end
  for k,b in pairs(tabButtons) do
   local selected=(k==mainPage)
   b.accentLine:SetAlpha(selected and 1 or 0)
   local c=selected and skin.soft or {.70,.74,.80}
   b.caption:SetTextColor(c[1],c[2],c[3])
  end
  for k,b in pairs(settingsButtons) do
   local selected=(mainPage=='settings' and db.settingsSection==k)
   b.stripe:SetAlpha(selected and 1 or .35)
   local c=selected and skin.soft or {.72,.77,.81}
   b.caption:SetTextColor(c[1],c[2],c[3])
  end
  if chosen=='general' and refreshGeneral then refreshGeneral() end
  if chosen=='fonts' and refreshFonts then refreshFonts() end
  if chosen=='style' and refreshStyle then refreshStyle() end
  if chosen=='animation' and animationPreview then animationPreview:Refresh(true) end
 end
 local function selectTab(key)
  mainPage=key
  markTabs()
 end
 local function selectSettingsSection(key)
  if key~='general' and key~='style' and key~='fonts' then return end
  db.settingsSection=key
  selectTab('settings')
 end
 local function nav(k,caption,y)
  local b=button(w,caption,15,y,162,43,function() selectTab(k) end)
  b.accentLine=fixedTexture(b,'TOPLEFT',0,0,4,43,1,.55,.22,1)
  uiAccentTextures[#uiAccentTextures+1]=b.accentLine
  b.accentLine:SetAlpha(0)
  tabButtons[k]=b
 end
 nav('settings','SETTINGS',-95)
 nav('animation','ANIMATION',-147)
 nav('help','HELP',-199)
 nav('about','ABOUT',-251)
 for i,entry in ipairs({{'general','GENERAL'},{'style','STYLE'},{'fonts','FONTS'}}) do
  local key,name=entry[1],entry[2]
  local b=button(settingsBar,name,2+(i-1)*167,-4,158,34,function() selectSettingsSection(key) end)
  settingsButtons[key]=b
  addResponsive(function(extra)
   local width=(490+extra-16)/3
   b:ClearAllPoints()
   b:SetPoint('TOPLEFT',settingsBar,'TOPLEFT',2+(i-1)*(width+8),-4)
   b:SetSize(width,34)
  end)
 end
 -- Top controls live in a raised, non-draggable region ABOVE full-window tabs.
 -- A single layout function keeps both slider tracks on the same row at any width.
 local topBar=CreateFrame('Frame',nil,w)
 topBar:SetPoint('TOPLEFT',w,'TOPLEFT',274,-7)
 topBar:SetPoint('TOPRIGHT',w,'TOPRIGHT',-25,-7)
 topBar:SetHeight(57)
 if topBar.SetFrameLevel and w.GetFrameLevel then topBar:SetFrameLevel(w:GetFrameLevel()+35) end
 if topBar.EnableMouse then topBar:EnableMouse(true) end
 local sliderGroups={}
 local function topSlider(key,title,minimum,maximum,apply)
  local heading=label(topBar,title,0,-5,10,.80,.84,.90)
  local current=label(topBar,'',0,-5,11,1,.70,.44)
  uiAccentTexts[#uiAccentTexts+1]=current
  local slider=CreateFrame('Slider',nil,topBar)
  slider:SetOrientation('HORIZONTAL')
  slider:SetSize(180,16)
  slider:SetMinMaxValues(minimum,maximum);slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  if slider.EnableMouse then slider:EnableMouse(true) end
  if slider.SetHitRectInsets then slider:SetHitRectInsets(0,0,-5,-5) end
  local track=slider:CreateTexture(nil,'BACKGROUND')
  track:SetPoint('LEFT',slider,'LEFT');track:SetPoint('RIGHT',slider,'RIGHT')
  track:SetHeight(5);tintTexture(track,{.30,.34,.40})
  slider:SetThumbTexture('Interface\\Buttons\\UI-SliderBar-Button-Horizontal')
  local thumb=slider:GetThumbTexture();if thumb then thumb:SetSize(20,23) end
  slider:SetScript('OnValueChanged',function(_,value)
   if type(value)~='number' then return end
   local n=math.floor(math.max(minimum,math.min(maximum,value))+.5)
   db[key]=n
   current:SetText(n..'%')
   apply(n)
  end)
  slider:SetValue(db[key] or 100)
  sliderGroups[#sliderGroups+1]={heading=heading,value=current,slider=slider}
  if key=='windowScale' then w._scaleSlider=slider else w._opacitySlider=slider end
 end
 topSlider('windowScale','WINDOW SCALE',75,120,function(n) w:SetScale(n/100) end)
 topSlider('windowOpacity','OPACITY',0,100,function(n) w:SetAlpha(n/100) end)
 local function positionTopSliders()
  local available=math.max(420,(w:GetWidth() or minWidth)-299)
  local gap=22
  local width=(available-gap)/2
  for i,group in ipairs(sliderGroups) do
   local x=(i-1)*(width+gap)
   group.heading:ClearAllPoints()
   group.heading:SetPoint('TOPLEFT',topBar,'TOPLEFT',x,-5)
   group.value:ClearAllPoints()
   group.value:SetPoint('TOPRIGHT',topBar,'TOPLEFT',x+width,-5)
   group.slider:ClearAllPoints()
   group.slider:SetPoint('TOPLEFT',topBar,'TOPLEFT',x,-34)
   group.slider:SetWidth(width-6)
  end
 end
 addResponsive(function() positionTopSliders() end)
 w._topSliderBar=topBar -- Sidebar footer follows the lower edge when the user resizes the window.
 local wow_name_version,wow_number_version=wowClientVersions()
 local footerRule=fixedTexture(w,'BOTTOMLEFT',16,70,158,1,.23,.27,.33,.9)
 local addonFooter=label(w,'ADDON  v'..addonVersion(),20,-657,10,1,.60,.29)
 addonFooter:ClearAllPoints();addonFooter:SetPoint('BOTTOMLEFT',w,'BOTTOMLEFT',20,51)
 local wowNameFooter=label(w,wow_name_version,20,-680,10,1,.60,.29)
 wowNameFooter:ClearAllPoints();wowNameFooter:SetPoint('BOTTOMLEFT',w,'BOTTOMLEFT',20,34)
 local wowNumberFooter=label(w,'v'..wow_number_version,20,-698,10,1,.60,.29)
 wowNumberFooter:ClearAllPoints();wowNumberFooter:SetPoint('BOTTOMLEFT',w,'BOTTOMLEFT',20,17)
 uiAccentTexts[#uiAccentTexts+1]=addonFooter
 uiAccentTexts[#uiAccentTexts+1]=wowNameFooter
 uiAccentTexts[#uiAccentTexts+1]=wowNumberFooter
 -- Dynamically refresh versions if the same options frame remains open across UI changes.
 w:SetScript('OnShow',function()
  local newName,newVersion=wowClientVersions()
  addonFooter:SetText('ADDON  v'..addonVersion())
  wowNameFooter:SetText(newName)
  wowNumberFooter:SetText('v'..newVersion)
 end)
 -- GENERAL: independent clickable on/off switches, with exclusive damage sources.
 header(general,'General','Addon status, combat source, log and Overkill',true)
 section(general,'ADDON STATUS',-195)
 local enabled=toggleRow(general,'Enable addon',-216,function()
  db.enabled=not db.enabled
  clearNumbers();clearQueues()
  if not db.enabled or db.damageSource=='player' then enableNative()
  else disableNative();if db.damageSource=='coverage' then enableFilteredLog() end end
  refreshGeneral()
 end)
 section(general,'COMBAT TEXT MODE',-259)
 local choices={}
 local sourceNames={coverage='Coverage  /  Melee, spells, DoT, heals, XP',player='Blizzard  /  Native damage',all='All damage  /  Unfiltered'}
 local function sourceChoice(key,y)
  local row=toggleRow(general,sourceNames[key],y,function()
   -- Sources are mutually exclusive. Turning a selected non-Coverage source
   -- off returns to Coverage; never leave the engine with no valid source.
   if db.damageSource==key then
    setSource(key=='coverage' and 'player' or 'coverage')
   else setSource(key) end
   refreshGeneral()
  end)
  choices[key]=row
 end
 sourceChoice('coverage',-281)
 sourceChoice('player',-317)
 sourceChoice('all',-353)
 section(general,'COMBAT LOG',-399)
 local logToggle=toggleRow(general,'Add Combat Log',-420,function()
  db.combatLogEnabled=not db.combatLogEnabled
  clearQueues()
  if db.combatLogEnabled then enableFilteredLog() end
  refreshGeneral()
 end)
 section(general,'PET DAMAGE',-463)
 local petAssistButton=toggleRow(general,'Add Pet Damage',-484,function()
  db.petAssist=not db.petAssist;clearQueues();refreshGeneral()
 end)
 section(general,'OVERKILL',-527)
 local killToggle=toggleRow(general,'Add Overkill',-548,function()
  db.showKillingBlow=not db.showKillingBlow
  if not db.showKillingBlow then clearOverkills() end
  refreshGeneral()
 end)
 valueSlider(general,'overkillDuration','Overkill duration',-591,' s')
 valueSlider(general,'overkillShakeIntensity','Overkill shake intensity',-637,' %')
 refreshGeneral=function()
  enabled:RefreshSwitch(db.enabled)
  for key,row in pairs(choices) do row:RefreshSwitch(db.damageSource==key) end
  logToggle:RefreshSwitch(db.combatLogEnabled~=false)
  petAssistButton:RefreshSwitch(db.petAssist)
  killToggle:RefreshSwitch(db.showKillingBlow)
 end
 -- TYPOGRAPHY / isolate font UI compatibility so other panels can always build.
 local typographyOK, typographyError = pcall(function()
 header(typeface,'Fonts','Select normal, critical and interface fonts',true)
 section(typeface,'COMBAT FONTS  /  LOCAL + LIBSHAREDMEDIA',-201)
 local fontSelectors={}
 local refreshSamples
 local function dropdown(key,name,y)
  label(typeface,name,220,y,12,.89,.91,.94)
  local selected=button(typeface,'',220,y-23,499,34,function() end)
  selected.caption:ClearAllPoints()
  selected.caption:SetPoint('LEFT',selected,'LEFT',15,0)
  selected.caption:SetJustifyH('LEFT')
  -- A separate right-side caret makes the font selector an obvious dropdown.
  local caret=selected:CreateFontString(nil,'OVERLAY','GameFontNormal')
  caret:SetPoint('RIGHT',selected,'RIGHT',-15,0)
  caret:SetFont(baseFonts['Arial Narrow'],17,'')
  caret:SetText('▼')
  caret:SetTextColor(.95,.74,.47)
  local popup=CreateFrame('Frame',nil,w)
  popup:SetFrameStrata('TOOLTIP')
  -- Older/custom clients may omit GetFrameLevel on certain widgets.
  if popup.SetFrameLevel and w.GetFrameLevel then
   local ok,level=pcall(w.GetFrameLevel,w)
   if ok and type(level)=='number' then popup:SetFrameLevel(level+20) end
  end
  popup:SetSize(499,230)
  if key=='uiFont' then
   popup:SetPoint('BOTTOMLEFT',selected,'TOPLEFT',0,2)
   popup:SetPoint('BOTTOMRIGHT',selected,'TOPRIGHT',0,2)
  else
   popup:SetPoint('TOPLEFT',selected,'BOTTOMLEFT',0,-2)
   popup:SetPoint('TOPRIGHT',selected,'BOTTOMRIGHT',0,-2)
  end
  colorTexture(popup,.105,.125,.16,.99)
  local search=CreateFrame('EditBox',nil,popup)
  search:SetPoint('TOPLEFT',10,-8);search:SetSize(467,25)
  search:SetPoint('TOPRIGHT',popup,'TOPRIGHT',-22,-8)
  search:SetAutoFocus(false)
  search:SetFont(baseFonts['Arial Narrow'],13,'')
  search:SetTextColor(1,.86,.70)
  -- Not every Forever build exposes SetTextInsets on EditBox.
  if search.SetTextInsets then search:SetTextInsets(8,8,0,0) end
  colorTexture(search,.16,.19,.24,1)
  search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
  local scroll=CreateFrame('ScrollFrame',nil,popup,'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT',9,-39);scroll:SetPoint('BOTTOMRIGHT',-27,9)
  local content=CreateFrame('Frame',nil,scroll)
  scroll:SetScrollChild(content)
  content:SetSize(463,1)
  popup:SetScript('OnSizeChanged',function(self)
   content:SetWidth(math.max(1,self:GetWidth()-36))
  end)
  local rows={}
  local function rebuild()
   local query=fontToken(search:GetText())
   local entries=availableFonts()
   local visible,lastGroup=0,nil
   for _,entry in ipairs(entries) do
    if query=='' or fontToken(entry.name):find(query,1,true) then
     if entry.group~=lastGroup then
      visible=visible+1
      local row=rows[visible]
      if not row then
       row=button(content,'',0,-(visible-1)*27,448,26,function() end)
       row:SetPoint('TOPRIGHT',content,'TOPRIGHT',-15,-(visible-1)*27)
       rows[visible]=row
      end
      row:Show();row.fontEntry=nil
      row.caption:SetText('  '..entry.group)
      row.caption:SetTextColor(1,.66,.37)
      row:SetScript('OnClick',function() end)
      lastGroup=entry.group
     end
     visible=visible+1
     local row=rows[visible]
     if not row then
      row=button(content,'',0,-(visible-1)*27,448,26,function() end)
      row:SetPoint('TOPRIGHT',content,'TOPRIGHT',-15,-(visible-1)*27)
      rows[visible]=row
     end
     row:Show();row.fontEntry=entry
     row.caption:SetText(entry.name..(entry.available and '' or '   [NOT INSTALLED]'))
     if db[key]==entry.name then row.caption:SetTextColor(1,.78,.47)
     elseif entry.available then row.caption:SetTextColor(.90,.92,.95)
     else row.caption:SetTextColor(.51,.55,.61) end
     row:SetScript('OnClick',function(self)
      local option=self.fontEntry
      if not option then return end
      if not option.available then
       say(option.name..' is not registered. Install a LibSharedMedia font pack and /reload.')
       return
      end
      db[key]=option.name
      if key=='uiFont' then refreshUIFont() end
      if refreshSamples then refreshSamples() end
      selected.caption:SetText(option.name)
      popup:Hide();search:ClearFocus()
     end)
    end
   end
   for i=visible+1,#rows do rows[i]:Hide() end
   content:SetHeight(math.max(1,visible*27))
   if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
  end
  search:SetScript('OnTextChanged',rebuild)
  selected:SetScript('OnClick',function()
   local wasOpen=popup:IsShown()
   for _,other in ipairs(fontPopups) do other:Hide() end
   if not wasOpen then
    search:SetText('')
    rebuild() -- Refresh LSM fonts registered since options were created.
    popup:Show()
   end
  end)
  fontPopups[#fontPopups+1]=popup
  popup:Hide()
  fontSelectors[key]=function() selected.caption:SetText(db[key] or defaultFont) end
 end
 dropdown('font','NORMAL DAMAGE   /   WHITE',-225)
 dropdown('critFont','CRITICAL DAMAGE   /   YELLOW',-288)
 section(typeface,'SIZE & OUTLINE',-361)
 valueSlider(typeface,'size','Font size',-386,' px')
 valueSlider(typeface,'critScale','Critical scale',-425,'×')
 local outline=toggleRow(typeface,'Font outline',-467,function()
  db.outline=not db.outline
  if refreshSamples then refreshSamples() end
  outline:RefreshSwitch(db.outline)
 end)
 section(typeface,'SETTINGS TYPOGRAPHY',-511)
 dropdown('uiFont','SETTINGS FONT   /   COMPACT UI',-533)
 -- Only a font registry/provider supplies third-party font data. This preview
 -- uses local sample numbers, never protected combat amounts.
 -- A FontString must receive a font before SetText() on WoW Forever.
 -- Give both previews Blizzard's built-in fallback first, then apply the
 -- selected font (setFont also handles unavailable SharedMedia paths).
 local normalPreview=typeface:CreateFontString(nil,'OVERLAY','GameFontNormal')
 normalPreview:SetPoint('TOPLEFT',220,-606)
 setFont(normalPreview,22,db.font)
 normalPreview:SetTextColor(1,1,1)
 normalPreview:SetText('12345')
 local critPreview=typeface:CreateFontString(nil,'OVERLAY','GameFontNormal')
 critPreview:SetPoint('TOPLEFT',481,-606)
 setFont(critPreview,26,db.critFont)
 critPreview:SetTextColor(1,.85,.15)
 critPreview:SetText('67890')
 refreshSamples=function()
  setFont(normalPreview,22,db.font)
  setFont(critPreview,26,db.critFont)
 end
 label(typeface,'WHITE  /  NORMAL',220,-637,10,.67,.72,.78)
 label(typeface,'YELLOW  /  CRITICAL',481,-637,10,.67,.72,.78)
 label(typeface,'Custom fonts: Fonts/CustomFonts.lua  /  LibSharedMedia packs supported.',220,-665,10,.61,.65,.71)
 refreshFonts=function()
  for _,redraw in pairs(fontSelectors) do redraw() end
  outline:RefreshSwitch(db.outline)
  refreshSamples()
 end
 end) -- Typography construction guard.
 if not typographyOK then
  -- A font-picker incompatibility must NEVER leave Animation or Help empty.
  refreshFonts=nil
  say('Typography panel compatibility error: '..tostring(typographyError))
  pcall(function()
   header(typeface,'Fonts','Font picker unavailable on this client; other sections are safe',true)
   label(typeface,'Try /reload or report the error shown in chat.',220,-183,12,1,.70,.42)
  end)
 end
 -- SETTINGS > STYLE: color presets tint only interface surfaces and controls.
 -- Never recolor floating combat text, native unit frames or game nameplates.
 header(stylePane,'Style','Choose a color theme for the addon interface',true)
 section(stylePane,'INTERFACE COLOR PRESETS',-207)
 local styleEntries={
  {'ember','EMBER ORANGE','Classic charcoal with warm orange accents'},
  {'glacier','GLACIER BLUE','Cool blue highlights and deep navy panels'},
  {'emerald','EMERALD','Dark forest panels with jade highlights'},
  {'amethyst','AMETHYST','Violet highlights and plum-colored panels'},
  {'graphite','GRAPHITE','Neutral monochrome white and grey'},
 }
 local styleCards={}
 local function applyUISkin()
  local skin=currentUISkin()
  tintTexture(windowBG,skin.window,.99)
  tintTexture(sidebar,skin.sidebar,.95)
  for _,tx in ipairs(uiAccentTextures) do tintTexture(tx,skin.accent) end
  for _,fs in ipairs(uiAccentTexts) do fs:SetTextColor(skin.soft[1],skin.soft[2],skin.soft[3]) end
  for _,b in ipairs(uiButtons) do
   tintTexture(b._skinBackground,b._skinAccent and skin.sidebar or skin.button)
   tintTexture(b._skinStripe,b._skinAccent and skin.accent or {.29,.34,.39})
   tintTexture(b._skinHover,skin.hover)
  end
  markTabs()
  if animationPreview and animationPreview.ApplyTheme then animationPreview:ApplyTheme() end
 end
 for i,entry in ipairs(styleEntries) do
  local key,name,description=entry[1],entry[2],entry[3]
  local y=-239-(i-1)*83
  local card=button(stylePane,'',220,y,499,72,function()
   db.uiColorStyle=key
   applyUISkin()
   if refreshStyle then refreshStyle() end
  end)
  card.caption:ClearAllPoints();card.caption:SetPoint('TOPLEFT',card,'TOPLEFT',18,-14)
  card.caption:SetJustifyH('LEFT')
  label(card,description,18,-42,11,.68,.73,.80)
  local swatch=fixedTexture(card,'TOPRIGHT',-18,-18,30,30,1,.59,.30,1)
  styleCards[key]={button=card,swatch=swatch,name=name}
 end
 refreshStyle=function()
  local skin=currentUISkin()
  for key,entry in pairs(styleCards) do
   local selected=(db.uiColorStyle==key)
   local color=UI_COLOR_STYLES[key].accent
   tintTexture(entry.swatch,color)
   entry.button.caption:SetText(entry.name)
   local c=selected and skin.soft or {.87,.90,.94}
   entry.button.caption:SetTextColor(c[1],c[2],c[3])
   tintTexture(entry.button.stripe,selected and skin.accent or {.29,.34,.39})
  end
 end
 label(stylePane,'Color presets affect the addon UI only, not combat numbers.',220,-672,11,.63,.69,.75)
 -- ANIMATION / split controls: motion at left, normal and critical offsets at right.
 header(animation,'Animation styles','Select a style and fine-tune its movement and hit positions')
 local subTabs,subButtons={},{}
 local subNames={arc='ARC',popup='POPUP',float='FLOAT',bounce='BOUNCE'}
 local subDescriptions={
  arc='Curved rising trajectory with directional travel',
  popup='Scale up, hold, then drift to either side and fade',
  float='Smooth vertical rise with gentle horizontal sway',
  bounce='Springy rise with damping and directional drift'
 }
 local animationSliders={}
 if _G.ShaaenFCTAnimationPreview then
  animationPreview=_G.ShaaenFCTAnimationPreview:Create(animation,function() return db end,setFont,motionAt,fadeAt,currentUISkin)
 end
 local function anchorTopLeft(widget,parent,x,y)
  widget:ClearAllPoints()
  widget:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y)
 end
 local function rightLabel(parent,title,x,y,size,r,g,b)
  local fs=label(parent,title,x,y,size,r,g,b)
  addResponsive(function(extra) anchorTopLeft(fs,parent,x+extra/2,y) end)
  return fs
 end
 -- Compact two-column slider, with a signed pixel readout for offsets.
 -- Range validation also applies to manual entry in the pixel input boxes.
 local function compactSlider(parent,key,title,x,y,suffix,pixelInput)
  local r=ranges[key]
  local titleText=label(parent,title,x,y,11,.88,.91,.94)
  local pixelSuffix
  local value
  local input
  if pixelInput then
   input=CreateFrame('EditBox',nil,parent)
   input:SetPoint('TOPLEFT',x+169,y+3)
   input:SetSize(46,21)
   input:SetAutoFocus(false)
   if input.SetMaxLetters then input:SetMaxLetters(6) end
   input:SetFont(resolveFont(db.uiFont or defaultUIFont),12,'OUTLINE')
   input:SetTextColor(1,.73,.42)
   input:SetJustifyH('RIGHT')
   colorTexture(input,.13,.15,.19,.95)
   pixelSuffix=label(parent,'px',x+219,y,10,.58,.62,.69)
  else
   value=label(parent,'',x+169,y,11,1,.73,.42)
   value:SetWidth(70)
  end
  local slider=CreateFrame('Slider',nil,parent)
  slider:SetOrientation('HORIZONTAL')
  slider:SetPoint('TOPLEFT',x+4,y-18)
  slider:SetSize(223,13)
  -- Split extra horizontal space evenly across motion and position columns.
  addResponsive(function(extra)
   local shift=(x>=475 and extra/2 or 0)
   anchorTopLeft(titleText,parent,x+shift,y)
   if input then anchorTopLeft(input,parent,x+169+shift+extra/2,y+3) end
   if value then anchorTopLeft(value,parent,x+169+shift+extra/2,y) end
   if pixelSuffix then anchorTopLeft(pixelSuffix,parent,x+219+shift+extra/2,y) end
   anchorTopLeft(slider,parent,x+4+shift,y-18)
   slider:SetWidth(223+extra/2)
  end)
  slider:SetMinMaxValues(r[1],r[2]);slider:SetValueStep(r[3])
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  local track=slider:CreateTexture(nil,'BACKGROUND')
  track:SetPoint('LEFT',slider,'LEFT',0,0);track:SetPoint('RIGHT',slider,'RIGHT',0,0)
  track:SetHeight(3)
  if track.SetColorTexture then track:SetColorTexture(.27,.30,.36,1)
  else track:SetTexture('Interface\\Buttons\\WHITE8X8');track:SetVertexColor(.27,.30,.36,1) end
  slider:SetThumbTexture('Interface\\Buttons\\UI-SliderBar-Button-Horizontal')
  local thumb=slider:GetThumbTexture()
  if thumb then thumb:SetSize(17,19) end
  local function show(num)
   local v=math.floor(num/r[3]+.5)*r[3]
   v=math.max(r[1],math.min(r[2],v))
   db[key]=math.floor(v*1000+.5)/1000
   if animationPreview then animationPreview:Refresh(false) end
   local formatted=string.format('%.'..r[4]..'f',db[key])
   if input then
    if not input:HasFocus() then input:SetText(formatted) end
   else value:SetText(formatted..(suffix or '')) end
  end
  slider:SetScript('OnValueChanged',function(_,n) show(n) end)
  slider:SetValue(db[key]);show(db[key])
  if input then
   local function apply()
    local typed=tonumber(input:GetText())
    if typed then
     typed=math.max(r[1],math.min(r[2],typed))
     slider:SetValue(typed)
     -- Setting the slider may round to the desired integer pixel value.
     input:SetText(string.format('%.'..r[4]..'f',db[key]))
    else input:SetText(string.format('%.'..r[4]..'f',db[key])) end
    input:ClearFocus()
   end
   input:SetScript('OnEnterPressed',apply)
   input:SetScript('OnEscapePressed',function(self)
    self:SetText(string.format('%.'..r[4]..'f',db[key]));self:ClearFocus()
   end)
   input:SetScript('OnEditFocusLost',function(self)
    local typed=tonumber(self:GetText())
    if typed then slider:SetValue(math.max(r[1],math.min(r[2],typed))) end
    self:SetText(string.format('%.'..r[4]..'f',db[key]))
   end)
  end
  animationSliders[key]={slider=slider,edit=input}
 end
 local profiles={
  arc={'duration','startY','rise','arc','curve','fade','direction','verticalDirection'},
  popup={'popupDuration','popupStartY','popupRise','popupPeak','popupIn','popupHold','popupFade','popupTravel','popupDirection','popupVerticalDirection'},
  float={'floatDuration','floatStartY','floatRise','floatDrift','floatSway','floatFade','floatDirection','floatVerticalDirection'},
  bounce={'bounceDuration','bounceStartY','bounceHeight','bouncePeak','bounceDecay','bounceFade','bounceTravel','bounceDirection','bounceVerticalDirection'}
 }
 for style,keys in pairs(profiles) do
  for _,suffix in ipairs({'NormalX','NormalY','CritX','CritY'}) do
   keys[#keys+1]=style..suffix
  end
 end
 local directionMenus={}
 local function selectAnimationStyle(key)
  db.animationStyle=key
  if animationPreview then animationPreview:Refresh(true) end
  for name,p in pairs(subTabs) do
   if name==key then p:Show() else p:Hide() end
  end
  for _,entries in pairs(directionMenus or {}) do
   for _,item in pairs(entries) do item.popup:Hide() end
  end
  for name,b in pairs(subButtons) do
   local chosen=name==key
   b.caption:SetTextColor(chosen and 1 or .72,chosen and .75 or .77,chosen and .48 or .81)
   b.stripe:SetAlpha(chosen and 1 or 0)
  end
 end
 for idx,key in ipairs({'arc','popup','float','bounce'}) do
  local x=216+(idx-1)*127
  subButtons[key]=button(animation,subNames[key],x,-306,119,34,function() selectAnimationStyle(key) end)
  local animButton=subButtons[key]
  addResponsive(function(extra)
   local width=(500+extra-24)/4
   animButton:SetSize(width,34)
   anchorTopLeft(animButton,animation,216+(idx-1)*(width+8),-306)
  end)
  local p=CreateFrame('Frame',nil,animation)
  p:SetAllPoints(animation);p:Hide();subTabs[key]=p
  label(p,subDescriptions[key],220,-352,11,.67,.71,.77)
  local separator=fixedTexture(p,'TOPLEFT',460,-378,1,322,.25,.28,.33,.8)
  addResponsive(function(extra) anchorTopLeft(separator,p,460+extra/2,-378) end)
  label(p,'MOTION / TIMING',222,-382,11,1,.63,.35)
  rightLabel(p,'NORMAL DAMAGE / POSITION',475,-382,10,1,.63,.35)
  compactSlider(p,key..'NormalX','Offset X',475,-403,' px',true)
  compactSlider(p,key..'NormalY','Offset Y',475,-440,' px',true)
  rightLabel(p,'CRITICAL DAMAGE / POSITION',475,-475,10,1,.63,.35)
  compactSlider(p,key..'CritX','Offset X',475,-499,' px',true)
  compactSlider(p,key..'CritY','Offset Y',475,-536,' px',true)
  rightLabel(p,'Signed offsets: X = horizontal / Y = vertical',475,-570,9,.63,.67,.72)
 end
 local arcPane=subTabs.arc
 compactSlider(arcPane,'duration','Duration',222,-403,' s')
 compactSlider(arcPane,'startY','Starting height',222,-440,' px')
 compactSlider(arcPane,'rise','Vertical rise',222,-477,' px')
 compactSlider(arcPane,'arc','Horizontal travel',222,-514,' px')
 compactSlider(arcPane,'curve','Arc curve',222,-551,' px')
 compactSlider(arcPane,'fade','Fade starts at',222,-588,' %')
 -- Horizontal and vertical direction selectors for each animation profile.
 -- Dropdown menus open upwards, so the 760px minimum window does not clip them.
 local directionFields={arc='direction',popup='popupDirection',float='floatDirection',bounce='bounceDirection'}
 local verticalFields={arc='verticalDirection',popup='popupVerticalDirection',float='floatVerticalDirection',bounce='bounceVerticalDirection'}
 local function redrawDirection(style)
  for _,entry in pairs(directionMenus[style] or {}) do
   local value=db[entry.field] or entry.default
   entry.trigger.caption:SetText(entry.title..': '..string.upper(value))
  end
 end
 for _,style in ipairs({'arc','popup','float','bounce'}) do
  local parent=subTabs[style]
  directionMenus[style]={}
  local function makeSelector(axis,title,field,y,options,default)
   local trigger=button(parent,'',475,y,238,31,function() end)
   trigger.caption:ClearAllPoints()
   trigger.caption:SetPoint('LEFT',trigger,'LEFT',10,0)
   trigger.caption:SetJustifyH('LEFT')
   local arrow=trigger:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
   arrow:SetPoint('RIGHT',trigger,'RIGHT',-10,0)
   arrow:SetText('▼')
   local popup=CreateFrame('Frame',nil,w)
   popup:SetFrameStrata('TOOLTIP')
   popup:SetSize(238,112)
   popup:SetPoint('BOTTOMLEFT',trigger,'TOPLEFT',0,3)
   popup:SetPoint('BOTTOMRIGHT',trigger,'TOPRIGHT',0,3)
   colorTexture(popup,.105,.125,.16,.99)
   local optionButtons={}
   for i,key in ipairs(options) do
    local row=button(popup,string.upper(key),8,-8-(i-1)*25,220,24,function()
     db[field]=key;popup:Hide();redrawDirection(style)
     if animationPreview then animationPreview:Refresh(true) end
    end)
    row:SetPoint('TOPRIGHT',popup,'TOPRIGHT',-8,-8-(i-1)*25)
    optionButtons[#optionButtons+1]=row
   end
   popup:Hide()
   trigger:SetScript('OnClick',function()
    local visible=popup:IsShown()
    for _,entries in pairs(directionMenus) do
     for _,item in pairs(entries) do item.popup:Hide() end
    end
    if not visible then popup:Show() end
   end)
   addResponsive(function(extra)
    local shift=extra/2
    anchorTopLeft(trigger,parent,475+shift,y)
    trigger:SetWidth(238+extra/2)
   end)
   directionMenus[style][axis]={field=field,trigger=trigger,popup=popup,title=title,default=default}
  end
  makeSelector('horizontal','HORIZONTAL',directionFields[style],-598,{'left','right','alternate','random'},'alternate')
  makeSelector('vertical','VERTICAL',verticalFields[style],-651,{'up','down','alternate','random'},'up')
  redrawDirection(style)
 end
 local popupPane=subTabs.popup
 compactSlider(popupPane,'popupDuration','Duration',222,-403,' s')
 compactSlider(popupPane,'popupStartY','Starting height',222,-440,' px')
 compactSlider(popupPane,'popupRise','Vertical travel',222,-477,' px')
 compactSlider(popupPane,'popupPeak','Peak size',222,-514,'×')
 compactSlider(popupPane,'popupIn','Pop-in duration',222,-551,' %')
 compactSlider(popupPane,'popupHold','Peak hold',222,-588,' %')
 compactSlider(popupPane,'popupFade','Fade starts at',222,-625,' %')
 compactSlider(popupPane,'popupTravel','Side travel',222,-662,' px')
 local floatPane=subTabs.float
 compactSlider(floatPane,'floatDuration','Duration',222,-403,' s')
 compactSlider(floatPane,'floatStartY','Starting height',222,-440,' px')
 compactSlider(floatPane,'floatRise','Vertical rise',222,-477,' px')
 compactSlider(floatPane,'floatDrift','Side drift',222,-514,' px')
 compactSlider(floatPane,'floatSway','Side sway',222,-551,' px')
 compactSlider(floatPane,'floatFade','Fade starts at',222,-588,' %')
 local bouncePane=subTabs.bounce
 compactSlider(bouncePane,'bounceDuration','Duration',222,-403,' s')
 compactSlider(bouncePane,'bounceStartY','Starting height',222,-440,' px')
 compactSlider(bouncePane,'bounceHeight','Bounce height',222,-477,' px')
 compactSlider(bouncePane,'bouncePeak','Peak size',222,-514,'×')
 compactSlider(bouncePane,'bounceDecay','Damping',222,-551,'')
 compactSlider(bouncePane,'bounceFade','Fade starts at',222,-588,' %')
 compactSlider(bouncePane,'bounceTravel','Side travel',222,-625,' px')
 local resetStyleButton=button(animation,'RESET THIS STYLE',220,-262,235,32,function()
  for _,key in ipairs(profiles[db.animationStyle] or profiles.arc) do db[key]=defaults[key] end
  for _,key in ipairs(profiles[db.animationStyle] or profiles.arc) do
   local widget=animationSliders[key]
   if widget then
    widget.slider:SetValue(defaults[key])
    if widget.edit then widget.edit:SetText(string.format('%d',defaults[key])) end
   end
  end
  redrawDirection(db.animationStyle)
  if animationPreview then animationPreview:Refresh(true) end
 end)
 local previewStyleButton=button(animation,'PREVIEW STYLE',469,-262,250,32,function()
  if not previewAnchor then
   previewAnchor=CreateFrame('Frame',nil,UIParent)
   previewAnchor:SetSize(160,12);previewAnchor:SetPoint('CENTER',UIParent,'CENTER',0,-80)
  end
  startNumber(previewAnchor,24580,false,true)
  startNumber(previewAnchor,8920,true,true)
 end,true)
 addResponsive(function(extra)
  local half=(499+extra-14)/2
  resetStyleButton:SetSize(half,32)
  anchorTopLeft(resetStyleButton,animation,220,-262)
  previewStyleButton:SetSize(half,32)
  anchorTopLeft(previewStyleButton,animation,220+half+14,-262)
 end)
 selectAnimationStyle(db.animationStyle or 'arc')
 -- ABOUT / separate from Help for a clean sidebar navigation.
 header(about,'About shaaenFCT','Floating Combat Text  /  Player & Guild')
 section(about,'WORLD OF WARCRAFT',-177)
 label(about,'I play World of Warcraft with the Les No Life guild (NL).',220,-208,13,.90,.93,.96)
 label(about,'shaaenFCT makes combat numbers easier to read and customize.',220,-236,12,.72,.77,.83)
 section(about,'MY GUILD',-290)
 label(about,'LES NO LIFE  /  NL',220,-320,17,1,.70,.39)
 label(about,'Guild community and shared adventures in WoW Forever.',220,-351,12,.72,.77,.83)
 section(about,'GUILD DISCORD',-411)
 label(about,'Les No Life community Discord',220,-440,11,.73,.77,.82)
 local guildDiscordURL='https://discord.gg/T6dYnaPsh'
 local discordInput=CreateFrame('EditBox',nil,about)
 discordInput:SetPoint('TOPLEFT',220,-467)
 discordInput:SetSize(493,30)
 discordInput:SetPoint('TOPRIGHT',about,'TOPRIGHT',-42,-467)
 discordInput:SetAutoFocus(false)
 discordInput:SetFont(baseFonts['Arial Narrow'],13,'')
 discordInput:SetTextColor(1,.88,.72)
 if discordInput.SetTextInsets then discordInput:SetTextInsets(8,8,0,0) end
 colorTexture(discordInput,.13,.15,.19,1)
 discordInput:SetText(guildDiscordURL)
 discordInput:SetScript('OnEnterPressed',function(self) self:HighlightText();self:SetFocus() end)
 discordInput:SetScript('OnEscapePressed',function(self) self:SetText(guildDiscordURL);self:ClearFocus() end)
 discordInput:SetScript('OnEditFocusLost',function(self) self:SetText(guildDiscordURL) end)
 button(about,'SELECT LINK FOR CTRL+C',220,-506,499,31,function()
  discordInput:SetText(guildDiscordURL)
  discordInput:SetFocus()
  discordInput:HighlightText()
 end,true)
 label(about,'Discord URL: '..guildDiscordURL,220,-561,11,.70,.78,.84)
 label(about,'Damage, incoming heals, XP, custom fonts and animation styles.',220,-614,11,.64,.69,.75)

 -- HELP / quick start and slash commands only.
 header(help,'Help','Quick start and slash commands')
 section(help,'QUICK START',-178)
 label(help,'1. Open Settings > General and select COVERAGE.',220,-209,12)
 label(help,'2. Open the Blizzard Combat Log.',220,-237,12)
 label(help,'3. Select My Actions (include Pet when relevant).',220,-265,12)
 label(help,'4. Attack a target with a visible nameplate.',220,-293,12)
 section(help,'SLASH COMMANDS',-347)
 label(help,'/sfct                 Open / close settings',220,-377,12)
 label(help,'/sfct open            Open settings',220,-405,12)
 label(help,'/sfct source coverage  Melee, spells, DoT, heal and XP',220,-433,12)
 label(help,'/sfct source player   Blizzard native damage',220,-461,12)
 label(help,'/sfct source all      Unfiltered damage',220,-489,12)
 label(help,'/sfct status          Compact status',220,-517,12)
 label(help,'/sfct plate traffic  Damage routing counts',220,-545,12)
 label(help,'/sfct pet on | off    Own pet target filter',220,-573,12)
 label(help,'/sfct ui reset          Restore scale and opacity to 100%.',220,-602,11,.69,.73,.77)
 -- Persistent action bar: buttons remain at the bottom-right while resizing.
 local footerLine=fixedTexture(w,'BOTTOMLEFT',207,56,506,1,.25,.28,.33,.85)
 footerLine:SetPoint('BOTTOMRIGHT',w,'BOTTOMRIGHT',-35,56)
 local closeFooterButton=button(w,'CLOSE',0,0,104,32,function() w:Hide() end)
 closeFooterButton:ClearAllPoints()
 closeFooterButton:SetPoint('BOTTOMRIGHT',w,'BOTTOMRIGHT',-39,12)
 local reloadFooterButton=button(w,'RELOAD UI',0,0,130,32,function()
  if InCombatLockdown and InCombatLockdown() then
   say('Reload UI after combat.');return
  end
  if type(ReloadUI)=='function' then ReloadUI()
  elseif type(_G.ReloadUI)=='function' then _G.ReloadUI()
  else say('Reload UI is not supported by this client.') end
 end,true)
 reloadFooterButton:ClearAllPoints()
 reloadFooterButton:SetPoint('RIGHT',closeFooterButton,'LEFT',-10,0)
 -- Apply initial geometry, including any previously saved resized dimensions.
 layoutTabs()
 applyUISkin()
 selectTab('settings')
 w:Hide()
 window=w
 return w
end
-- Open from the minimap without depending on the /sfct command wrapper.
-- At 0% opacity the window is technically shown but completely invisible.
-- Always provide a recovery path when the player clicks the minimap icon.
local function openSettingsCentered()
 if not db then return false,'SavedVariables not initialized' end
 local w=createWindow()
 if not w then return false,'Settings window unavailable' end
 if type(db.windowOpacity)~='number' or db.windowOpacity<10 then
  db.windowOpacity=100
  if w._opacitySlider then w._opacitySlider:SetValue(100) end
 end
 if type(db.windowScale)~='number' or db.windowScale<75 or db.windowScale>120 then
  db.windowScale=100
  if w._scaleSlider then w._scaleSlider:SetValue(100) end
 end
 -- Force a known visible position and alpha; a hidden frame still reports
 -- IsShown() = true after :Show() if its inherited opacity remains zero.
 w:SetAlpha(db.windowOpacity/100)
 w:SetScale(db.windowScale/100)
 w:ClearAllPoints()
 w:SetPoint('CENTER',UIParent,'CENTER',0,0)
 db.windowX=0;db.windowY=0
 w:Show()
 if type(w.Raise)=='function' then pcall(w.Raise,w) end
 return true
end
_G.ShaaenFCTOpenSettings=openSettingsCentered

local function status()
 say('v'..addonVersion()..' / '..(db.enabled and 'ENABLED' or 'DISABLED')..' / Source: '..db.damageSource)
 say('MATCHING: log='..smartStats.messages..', protected='..smartStats.hidden..', matched='..smartStats.matched..', discarded='..smartStats.discarded..', errors='..smartStats.failed..', flow='..tostring(smartFlow))
 say('PETS: own target filter='..tostring(db.petAssist)..', candidates='..petStats.candidates..', log matched='..petStats.matched..', unverified hits discarded')
 local stats=plateDisplay and plateDisplay:Statistics() or {}
 say('COVERAGE: physical='..coverageStats.physical..', magical='..coverageStats.magical..', unknown='..coverageStats.unknown..', log credited='..coverageStats.credited..', solo fallback='..coverageStats.soloFallback..', target alias='..coverageStats.targetAlias..', aliases ignored='..coverageStats.aliasSkipped..', zeros suppressed='..coverageStats.zeroSuppressed..', no evidence='..coverageStats.unverified..', tracked casts/swings='..coverageStats.tracked)
 say('PLAYER FRAMES: green heals='..playerTextStats.heals..', violet XP='..playerTextStats.xp..', XP unavailable='..playerTextStats.ignored)
 say('NAMEPLATE FRAMES: '..(db.plateDisplayEnabled and 'ON' or 'OFF')..', attached hits='..plateRenderStats.anchored..', fallback='..plateRenderStats.fallback..', created='..(stats.created or 0)..', active anchors='..(stats.attached or 0)..', releases='..(stats.removed or 0)..', anchor errors='..(stats.failed or 0))
 say('FINAL HITS: late='..killStats.late..', kills='..killStats.signals..', matched numbers='..killStats.numeric..', extended='..killStats.effects..', no damage amount='..killStats.labels..', unmatched='..killStats.unmatched..', inferred='..killStats.inferred..', removed plates='..killStats.removed..', UNIT_DIED='..killStats.died..', resolved kills='..killStats.lateSignals..', target fallback='..killFallbackStats.target..', recent hit='..killFallbackStats.personal..', nameplate missing='..killFallbackStats.noNameplate..', location missing='..killFallbackStats.noPosition)
end
-- Isolate nameplate lifetime handlers from the central OnEvent callback.
-- WoW Forever limits a single Lua function to 60 captured upvalues.
local function onNameplateAdded(unit)
  recentPlates[unit]=nil
  if db and db.enabled and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
   local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,unit)
   if ok and plate then
    -- Blizzard may reuse the frame: discard the previous enemy's DoT history.
    coverageTargets[plate]=nil
    coveragePlateEvents[plate]=nil
    coverageCastPlates[plate]=nil
    -- Blizzard can reuse a nameplate for a new unit: freeze its old FX first.
    freezeOverkillsForPlate(plate,platePositions[plate])
    for i=#pendingKills,1,-1 do
     if pendingKills[i].plate==plate then
      -- Resolve a pending previous kill before this plate is recycled.
      table.remove(pendingKills,i)
      local info=lastHits[plate]
      if db.showKillingBlow and info and GetTime()-info.at<=1.65 then
       if not killDecorated[plate] or killDecorated[plate]~=killScheduled[plate] then
        if spawnFinalNumberAt(info,plate,platePositions[plate] or info.position,true) then
         killDecorated[plate]=killScheduled[plate]
         killStats.numeric=killStats.numeric+1
        end
       end
      else killStats.labels=killStats.labels+1 end
     end
    end
    killScheduled[plate]=nil;killDecorated[plate]=nil;lastHits[plate]=nil;lastShown[plate]=nil;inferredAt[plate]=nil;foreignKillPlates[plate]=nil;confirmedPersonalKills[plate]=nil
    if lastPersonalPlate==plate then lastPersonalPlate,lastPersonalAt=nil,nil end
    if lastTargetPlate==plate then lastTargetPlate,lastTargetAt=nil,nil end
    -- Unmount old visual frames before Blizzard reuses the plate for a new mob.
    detachNumbers(plate,platePositions[plate])
    if plateDisplay then plateDisplay:Forget(plate) end
    -- Detached final-hit frames must never follow the newly reused plate.
    platePositions[plate]=nil
    plates[unit]=plate
    plateGuids[unit]=safeGUID(unit)
    rememberPosition(plate)
    if isUnitTarget(unit) then lastTargetPlate,lastTargetAt=plate,GetTime() end
   end
  end
end
local function onNameplateRemoved(unit)
  -- Check while the unit token is still meaningful; afterward the client
  -- may erase the GUID and the nameplate frame immediately.
  local died=safeDead(unit)
  rememberRemoved(unit)
  if plates[unit] then
   coverageTargets[plates[unit]]=nil
   coveragePlateEvents[plates[unit]]=nil
   coverageCastPlates[plates[unit]]=nil
  end
  if plateDisplay and plates[unit] then plateDisplay:Forget(plates[unit]) end
  if recentPlates[unit] then
   killStats.removed=killStats.removed+1
   if died then
    recentPlates[unit].confirmed=true
    local plate=recentPlates[unit].plate
    local info=lastHits[plate]
    if db and db.enabled and db.showKillingBlow and db.damageSource~='player'
       and info and GetTime()-info.at<=LAST_HIT_WINDOW then
     schedulePersonalKill(plate,GetTime())
    end
   end
  end
  plates[unit]=nil
  plateGuids[unit]=nil
end
engine:SetScript('OnEvent',function(_,event,...)
 if event=='ADDON_LOADED' then
  local name=...
  if name~=ADDON and name~='shaaenFCT' then return end
  shaaenFCTDB=type(shaaenFCTDB)=='table' and shaaenFCTDB or {}
  db=shaaenFCTDB
  for key,value in pairs(defaults) do if db[key]==nil then db[key]=value end end
  -- Upgrade users who still have the old default font PAIR; custom selections
  -- (including custom critical fonts) are never overwritten.
  if not db.arialDefaultsMigrated then
   if db.font=='Friz Quadrata TT' and db.critFont=='BigDam' then
    db.font='Arial';db.critFont='Arial'
   end
   db.arialDefaultsMigrated=true
  end
  -- Upgrade legacy Overkill presets to a numeric percentage.
  if db.overkillShakeIntensity=='light' then db.overkillShakeIntensity=25
  elseif db.overkillShakeIntensity=='medium' then db.overkillShakeIntensity=50
  elseif db.overkillShakeIntensity=='strong' then db.overkillShakeIntensity=85 end
  for key,range in pairs(ranges) do
   if type(db[key])~='number' then db[key]=defaults[key] end
   db[key]=math.max(range[1],math.min(range[2],db[key]))
  end
  if type(db.showKillingBlow)~='boolean' then db.showKillingBlow=true end
  if type(db.plateDisplayEnabled)~='boolean' then db.plateDisplayEnabled=true end
  if type(db.petAssist)~='boolean' then db.petAssist=true end
  if type(db.combatLogEnabled)~='boolean' then db.combatLogEnabled=true end
  if type(db.discordInvite)~='string' then db.discordInvite='' end
  if not UI_COLOR_STYLES[db.uiColorStyle] then db.uiColorStyle='ember' end
  if db.settingsSection~='general' and db.settingsSection~='style' and db.settingsSection~='fonts' then db.settingsSection='general' end
  if type(db.windowScale)~='number' or db.windowScale~=db.windowScale then db.windowScale=100 end
  db.windowScale=math.max(75,math.min(120,math.floor(db.windowScale+.5)))
  if type(db.windowOpacity)~='number' or db.windowOpacity~=db.windowOpacity then db.windowOpacity=100 end
  db.windowOpacity=math.max(0,math.min(100,math.floor(db.windowOpacity+.5)))
  for _,field in ipairs({'direction','popupDirection','floatDirection','bounceDirection'}) do
   if db[field]~='alternate' and db[field]~='left' and db[field]~='right' and db[field]~='random' then
    db[field]='alternate'
   end
  end
  for _,field in ipairs({'verticalDirection','popupVerticalDirection','floatVerticalDirection','bounceVerticalDirection'}) do
   if db[field]~='up' and db[field]~='down' and db[field]~='alternate' and db[field]~='random' then db[field]='up' end
  end
  if db.animationStyle~='arc' and db.animationStyle~='popup' and db.animationStyle~='float' and db.animationStyle~='bounce' then db.animationStyle='arc' end
  -- v0.7.42 removes the selectable Smart mode. Keep player / all choices.
  if db.damageSource~='coverage' and db.damageSource~='player' and db.damageSource~='all' then db.damageSource='coverage' end
  db.settingsVersion=9
  if db.enabled then
   if db.damageSource=='player' then enableNative() else disableNative() end
   if db.damageSource=='coverage' then enableFilteredLog() end
  end
  say('v'..addonVersion()..' loaded / '..db.damageSource..' mode /sfct')
 elseif event=='PLAYER_LOGIN' then
  xpPrevious,xpPreviousMax=snapshotXP()
  if db and db.enabled and db.damageSource=='coverage' then enableFilteredLog() end
 elseif event=='PLAYER_ENTERING_WORLD' or event=='PLAYER_REGEN_ENABLED' then
  if event=='PLAYER_ENTERING_WORLD' then xpPrevious,xpPreviousMax=snapshotXP() end
  if db and db.enabled and db.damageSource=='player' then enableNative() end
 elseif event=='PLAYER_XP_UPDATE' then
  showXPUpdate()
 elseif event=='UNIT_SPELLCAST_SUCCEEDED' then
  local unit=...
  if unit=='player' then coverageTrack('target',true)
  elseif unit=='pet' and db.petAssist then coverageTrack('pettarget',true) end
 elseif event=='PLAYER_SWING' then
  coverageTrack('target')
 elseif event=='COMBAT_LOG_MESSAGE' then
  local message,_,_,_,order=...
  local ok=pcall(onFilteredCombatMessage,message,order)
  if not ok then smartStats.failed=smartStats.failed+1 end
 elseif event=='NAME_PLATE_UNIT_ADDED' then
  onNameplateAdded(...)
 elseif event=='NAME_PLATE_UNIT_REMOVED' then
  onNameplateRemoved(...)
 elseif event=='PARTY_KILL' then
  local attackerGUID,victimGUID=...
  notePersonalKill(attackerGUID,victimGUID)
 elseif event=='UNIT_DIED' then
  local guid=...
  if safeValue(guid) and type(guid)=='string' then
   killStats.died=killStats.died+1
   for _,entry in pairs(recentPlates) do
    if entry.guid and entry.guid==guid then entry.confirmed=true end
   end
   noteUnitDeath(guid)
  end
 elseif event=='UNIT_COMBAT' then
  if not db or not db.enabled or (db.damageSource~='coverage' and db.damageSource~='all') then return end
  local unit,action,descriptor,amount,school=...
  -- UNIT_COMBAT announces damage TAKEN, never the attacker.
  -- Ignore normal target/softenemy aliases to prevent duplicates.
  -- Once the mob is readably dead, a soft token may be the sole late signal.
  if type(unit)~='string' or not safeValue(action) then return end
  if unit=='player' then
   -- Keep the amount untouched: on Forever it may be a secret combat value.
   -- A heal on someone else or the pet is deliberately not displayed here.
   if action=='HEAL' or action=='HEALED' then
    local anchor=(db.damageSource=='coverage' and playerDisplay and playerDisplay:Attach('heal')) or playerHealAnchor()
    local critical=safeValue(descriptor) and descriptor=='CRITICAL'
    local ok,shown=pcall(startNumber,anchor,amount,critical,false,false,nil,true)
    if not ok or not shown then smartStats.failed=smartStats.failed+1
    else playerTextStats.heals=playerTextStats.heals+1 end
   end
   return
  end
  -- UNIT_COMBAT's BLOCK action may include a numeric amount. The old code
  -- replaced that amount with the literal BLOCK, making blocked values vanish.
  -- Render positive/readable amounts (or protected amounts) directly and show
  -- a separate BLOCKED label. A full/zero block remains a BLOCK notice.
  -- WOUND/DAMAGE with BLOCKED descriptor is still actual outgoing damage.
  local blockedResult=action=='BLOCK' or action=='BLOCKED'
  local blockedModifier=safeValue(descriptor) and (descriptor=='BLOCK' or descriptor=='BLOCKED')
  local hasBlockAmount=false
  if blockedResult then
   if not safeValue(amount) then hasBlockAmount=true
   elseif type(amount)=='number' and amount>0 then hasBlockAmount=true end
  end
  local notice
  if action=='MISS' or action=='MISSED' then notice='MISS'
  elseif action=='DODGE' or action=='DODGED' then notice='DODGE'
  elseif action=='PARRY' or action=='PARRIED' then notice='PARRY'
  elseif blockedResult then
   if not hasBlockAmount then notice='BLOCK' end
  elseif action~='WOUND' and action~='DAMAGE' then return end
  if notice then amount=notice end
  -- Preserve numeric combat values (including secret values) without reading
  -- or formatting them. Only the separately rendered status is a string.
  local blockKind=not notice and (blockedResult and 'result' or (blockedModifier and 'modified' or nil))
  local isGlancing=not notice and not blockKind and safeValue(descriptor) and descriptor=='GLANCING'
  local critical=not notice and safeValue(descriptor) and descriptor=='CRITICAL'
  local plate
  if unit:match('^nameplate%d+$') then
   plate=plates[unit]
   if not plate and recentPlates[unit] and GetTime()-recentPlates[unit].at<DEATH_GRACE then
    plate=recentPlates[unit].plate
   end
   if not plate and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
    local ok,p=pcall(C_NamePlate.GetNamePlateForUnit,unit)
    if ok and p then plate=p;plates[unit]=p end
   end
  elseif (unit=='softinteract' or unit=='softenemy' or unit=='target') then
   if db.damageSource=='coverage' and unit=='target' then plate=livePlateForUnit(unit) end
   if not plate then
    local entry=findLatePlateForUnit(unit)
    if entry then plate=entry.plate end
   end
  end
  if not plate then return end
  local now=GetTime()
  -- Do not treat the same target/nameplate report as two separate hits.
  -- Prefer the nameplate token, because it stays tied to its actual target.
  if db.damageSource=='coverage' then
   if unit:match('^nameplate%d+$') then
    coveragePlateEvents[plate]={at=now,action=action}
    for i=#smartPending,1,-1 do
     local hit=smartPending[i]
     if hit.coverageAlias and hit.plate==plate and hit.coverageAction==action
       and now-hit.at<=COVERAGE_ALIAS_WINDOW and now-hit.at>=0 then
      table.remove(smartPending,i);coverageStats.aliasSkipped=coverageStats.aliasSkipped+1
     end
    end
   elseif unit=='target' and coverageAliasDuplicate(plate,action,now) then
    coverageStats.aliasSkipped=coverageStats.aliasSkipped+1
    return
   elseif unit=='target' then coverageStats.targetAlias=coverageStats.targetAlias+1 end
   -- Only inspect ordinary numbers. Protected amounts must pass unchanged
   -- to FontString:SetText() and cannot be tested for zero.
   if not notice and safeValue(amount) and type(amount)=='number' and amount<=0 then
    coverageStats.zeroSuppressed=coverageStats.zeroSuppressed+1
    return
   end
  end
  if db.damageSource=='coverage' then
   queueSmartHit(unit,plate,amount,critical,notice,isGlancing,blockKind,coverageKind(school,notice),action)
  else
   local late=recentForPlate(plate)~=nil
   local ok,shown=pcall(startNumber,plate,amount,critical,false,late,notice,false,isGlancing,blockKind)
   if ok and shown then if not notice and blockKind~="result" then lastShown[plate]=GetTime();if late then killStats.late=killStats.late+1 end end
   else smartStats.failed=smartStats.failed+1 end
  end
 end
end)
engine:RegisterEvent('ADDON_LOADED')
engine:RegisterEvent('PLAYER_LOGIN')
engine:RegisterEvent('PLAYER_ENTERING_WORLD')
engine:RegisterEvent('PLAYER_REGEN_ENABLED')
engine:RegisterEvent('NAME_PLATE_UNIT_ADDED')
engine:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
local function registerOptional(name)
 local ok=pcall(function() engine:RegisterEvent(name) end)
 if not ok then say('Event unavailable: '..name) end
end
registerOptional('COMBAT_LOG_MESSAGE')
registerOptional('UNIT_COMBAT')
registerOptional('PLAYER_XP_UPDATE')
registerOptional('UNIT_SPELLCAST_SUCCEEDED')
registerOptional('PLAYER_SWING')
registerOptional('PARTY_KILL')
registerOptional('UNIT_DIED')
SLASH_SHAAENFCT1='/sfct'
SLASH_SHAAENFCT2='/shaaenfct'
SlashCmdList.SHAAENFCT=function(msg)
 if not db then say('Addon not initialized.');return end
 msg=(msg or ''):lower():match('^%s*(.-)%s*$')
 if msg=='source coverage' or msg=='source complete' then
  setSource('coverage');say('COVERAGE: all UNIT_COMBAT damage on tracked targets (solo best-effort); nameplate frames ON')
  db.plateDisplayEnabled=true;return
 end
 if msg=='source smart' or msg=='source experimental' then setSource('coverage');say('SMART mode was removed; using COVERAGE.');return end
 if msg=='source player' or msg=='source moi' then setSource('player');say('Blizzard source: your damage only');return end
 if msg=='source all' or msg=='source tous' then setSource('all');say('Addon source: all damage (including other players)');return end
 if msg=='source' then say('Current source: '..db.damageSource);return end
 if msg=='plate on' or msg=='plate off' then
  db.plateDisplayEnabled=msg=='plate on'
  clearNumbers()
  say('Nameplate-attached frames: '..(db.plateDisplayEnabled and 'ON' or 'OFF'))
  return
 end
 if msg=='player preview' then
  local heal=(playerDisplay and playerDisplay:Attach('heal')) or playerHealAnchor()
  local xp=(playerDisplay and playerDisplay:Attach('xp')) or playerHealAnchor()
  local okA,a=pcall(startNumber,heal,1234,false,true,false,nil,true)
  local okB,b=pcall(startNumber,xp,'+250 XP',false,true,false,nil,true,nil,nil,nil,true)
  say('Player frames preview: heal='..tostring(okA and a)..', XP='..tostring(okB and b))
  return
 end
 if msg=='plate traffic' then
  say('COVERAGE EVENTS: physical='..coverageStats.physical..', magical='..coverageStats.magical..', unknown='..coverageStats.unknown..', log credited='..coverageStats.credited..', solo fallback='..coverageStats.soloFallback..', alias skipped='..coverageStats.aliasSkipped..', no evidence='..coverageStats.unverified)
  say('DoT ticks are included with victim damage when available. UNIT_COMBAT alone does not reliably identify an individual DoT or its attacker.')
  return
 end
 if msg=='plate status' then
  local stats=plateDisplay and plateDisplay:Statistics() or {}
  say('COVERAGE: physical='..coverageStats.physical..', magical='..coverageStats.magical..', unknown='..coverageStats.unknown..', log credited='..coverageStats.credited..', solo fallback='..coverageStats.soloFallback..', target alias='..coverageStats.targetAlias..', aliases ignored='..coverageStats.aliasSkipped..', zeros suppressed='..coverageStats.zeroSuppressed..', no evidence='..coverageStats.unverified..', tracked casts/swings='..coverageStats.tracked)
 say('PLAYER FRAMES: green heals='..playerTextStats.heals..', violet XP='..playerTextStats.xp..', XP unavailable='..playerTextStats.ignored)
 say('NAMEPLATE FRAMES: '..(db.plateDisplayEnabled and 'ON' or 'OFF')..', attached hits='..plateRenderStats.anchored..', fallback='..plateRenderStats.fallback..', created='..(stats.created or 0)..', anchors='..(stats.attached or 0)..', recycled='..(stats.reused or 0)..', errors='..(stats.failed or 0))
  return
 end
 if msg=='plate preview' then
  local targetPlate
  for unit,plate in pairs(plates) do
   if isUnitTarget(unit) then targetPlate=plate;break end
  end
  if not targetPlate and C_NamePlate and type(C_NamePlate.GetNamePlateForUnit)=='function' then
   local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,'target')
   if ok then targetPlate=plate end
  end
  local visible=targetPlate~=nil
  if visible and targetPlate.IsShown then
   local ok,shown=pcall(targetPlate.IsShown,targetPlate)
   visible=ok and safeValue(shown) and shown==true
  end
  if visible then
   local ok,shown=pcall(startNumber,targetPlate,1234,false,true,false)
   if ok and shown then
    plateRenderStats.preview=plateRenderStats.preview+1
    say('Nameplate frame preview: 1234')
    return
   end
  end
  say('Preview unavailable: target an enemy with a visible nameplate.')
  return
 end
 if msg=='pet on' then db.petAssist=true;clearQueues();say('Own pet target enabled. Select My Actions in the Combat Log (include Pet and Misses).');return end
 if msg=='pet off' then db.petAssist=false;clearQueues();say('Own pet target disabled. Only your selected target is eligible for log-confirmed hits.');return end
 if msg=='pet' then say('Own pet target: '..(db.petAssist and 'ON' or 'OFF')..'. Coverage can use solo fallback; group hits require credits.');return end
 if msg=='status' or msg=='debug' then status();return end
 if msg=='overkilltest' or msg=='finaltest' then
  local targetPlate
  for unit,plate in pairs(plates) do
   if isUnitTarget(unit) then targetPlate=plate;break end
  end
  if not targetPlate and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
   local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,'target')
   if ok then targetPlate=plate end
  end
  local visible=targetPlate~=nil
  if visible and targetPlate.IsShown then
   local ok,shown=pcall(targetPlate.IsShown,targetPlate)
   visible=ok and safeValue(shown) and shown==true
  end
  if visible and spawnFinalNumberAt({amount=9999},targetPlate) then
   say('Preview: sample 9999 on the selected enemy nameplate')
  else
   say('Cannot preview: select an enemy with a visible nameplate, then /sfct overkilltest.')
  end
  return
 end
 if msg=='ui reset' or msg=='windowreset' then
  db.windowScale=100;db.windowOpacity=100
  if window then
   window:SetScale(1);window:SetAlpha(1)
   if window._scaleSlider then window._scaleSlider:SetValue(100) end
   if window._opacitySlider then window._opacitySlider:SetValue(100) end
   window:Show()
  else createWindow():Show() end
  say('Settings scale and opacity restored to 100%.')
  return
 end
 if msg=='center' or msg=='open center' or msg=='minimap open' then
  local ok,err=pcall(openSettingsCentered)
  if not ok then say('Unable to open settings: '..tostring(err)) end
  return
 end
 if msg=='open' or msg=='options' then createWindow():Show();return end
 if msg=='close' then if window then window:Hide() end;return end
 if msg=='off' then db.enabled=false;clearNumbers();clearQueues();enableNative();say('disabled');return end
 if msg=='on' then db.enabled=true;setSource(db.damageSource);say('enabled');return end
 local w=createWindow()
 if w:IsShown() then w:Hide() else w:Show() end
end
