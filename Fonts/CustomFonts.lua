-- shaaenFCT local custom font registry.
-- 1. Place .ttf or .otf files in Interface/AddOns/shaaenFCT/Fonts/
-- 2. Add an entry to the table below, using the exact file name.
-- 3. /reload and select the font in Typography.
-- Font binaries are NOT distributed with this addon.
-- Add only fonts that you are licensed to use.
local media=shaaenFCTMedia
if not media then return end
local localFonts={
 -- {'My Custom Font', 'MyFont.ttf'},
 -- {'BigDam', 'BigDam.ttf'},
 -- {'Numen', 'Numen.ttf'},
 -- {'Ellesmere', 'Expressway.ttf'},
}
for _,font in ipairs(localFonts) do
 if type(font[1])=='string' and type(font[2])=='string'
  and (font[2]:lower():match('^[%w%._%-]+%.ttf$') or font[2]:lower():match('^[%w%._%-]+%.otf$')) then
  media:Register('font',font[1],'Interface\\AddOns\\shaaenFCT\\Fonts\\'..font[2])
 end
end
