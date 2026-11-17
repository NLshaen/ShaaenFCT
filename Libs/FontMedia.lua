-- shaaenFCT embedded font media bridge.
-- When the official LibSharedMedia-3.0 is installed, it is used directly.
-- Otherwise a small font-only local registry provides the same Register,
-- Fetch and List signatures for the shaaenFCT font picker. The fallback is
-- addon-local and deliberately DOES NOT impersonate or replace the full LSM.
local ADDON = ...
-- Declare the local registry before getOfficial() is defined: Lua captures
-- locals only when they are already in lexical scope.
local fonts = {}
local synchronizedLib
local function getOfficial()
 if type(LibStub)=='table' or type(LibStub)=='function' then
  local ok,lib=pcall(function() return LibStub('LibSharedMedia-3.0',true) end)
  if ok and lib and type(lib.Register)=='function' and type(lib.Fetch)=='function' then
   if synchronizedLib~=lib then
    synchronizedLib=lib
    for name,path in pairs(fonts) do pcall(lib.Register,lib,'font',name,path) end
   end
   return lib
  end
 end
end
local bridge={}
function bridge:IsLocal(name) return fonts[name]~=nil end
function bridge:Register(kind,name,path)
 if kind~='font' or type(name)~='string' or name=='' or type(path)~='string' or path=='' then return false end
 fonts[name]=path
 local lib=getOfficial()
 if lib then pcall(lib.Register,lib,'font',name,path) end
 return true
end
function bridge:Fetch(kind,name,noDefault)
 if kind~='font' then return nil end
 local lib=getOfficial()
 if lib then
  local ok,path=pcall(lib.Fetch,lib,'font',name,true)
  if ok and type(path)=='string' and path~='' then return path end
 end
 if fonts[name] then return fonts[name] end
 if not noDefault then return 'Fonts\\FRIZQT__.TTF' end
end
function bridge:List(kind)
 if kind~='font' then return {} end
 local names,used={},{}
 local lib=getOfficial()
 if lib and type(lib.List)=='function' then
  local ok,registered=pcall(lib.List,lib,'font')
  if ok and type(registered)=='table' then
   for _,name in ipairs(registered) do
    if type(name)=='string' and not used[name] then names[#names+1]=name;used[name]=true end
   end
  end
 end
 for name in pairs(fonts) do if not used[name] then names[#names+1]=name;used[name]=true end end
 table.sort(names)
 return names
end
-- Use our local registry only when present; Core.lua knows this bridge.
_G.shaaenFCTMedia=bridge
-- Register packaged Blizzard fonts as known-good fallbacks.
bridge:Register('font','Friz Quadrata TT','Fonts\\FRIZQT__.TTF')
bridge:Register('font','Arial Narrow','Fonts\\ARIALN.TTF')
bridge:Register('font','Morpheus','Fonts\\MORPHEUS.TTF')
bridge:Register('font','Skurri','Fonts\\SKURRI.TTF')
