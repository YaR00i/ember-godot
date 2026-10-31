-- Deterministic native-size montage; never rewrite downloaded references.
local dir=assert(app.params.dir)
local files={'mage.png','mage_wonder_dungeon.png','mage_lady_scarlet.png','summoner.png','assassin.png','assassin_bloodline.png','assassin_cecilia.png'}
local board=Image(208,144,ColorMode.RGB)
board:clear(app.pixelColor.rgba(203,211,216,255))
for n,name in ipairs(files) do
 local s=app.open(dir..'/'..name);local img=Image(s)
 local col=(n-1)%4;local row=math.floor((n-1)/4)
 board:drawImage(img,Point(col*52+math.floor((52-img.width)/2),row*72+64-img.height))
end
board:resize(1248,864);board:saveAs(dir..'/comparison_6x.png')
print('Seven references; integer 6x montage; downloaded originals unchanged.')
