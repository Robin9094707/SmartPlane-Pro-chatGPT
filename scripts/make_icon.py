"""Generate original, code-drawn app artwork. Requires Pillow only."""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import json, math
root = Path(__file__).resolve().parents[1]
dest = root/'SmartPlane/Assets.xcassets/AppIcon.appiconset'
dest.mkdir(parents=True, exist_ok=True)
size=1024
im=Image.new('RGB',(size,size)); px=im.load()
for y in range(size):
    for x in range(size):
        g=max(0,1-math.hypot(x-780,y-210)/1050)
        px[x,y]=(int(5+g*5),int(22+g*35),int(37+g*40))
d=ImageDraw.Draw(im)
for r in (240,340,450): d.ellipse((512-r,512-r,512+r,512+r),outline=(35,74,85),width=2)
points=[(.5,.07),(.54,.15),(.55,.36),(.9,.52),(.93,.63),(.56,.53),(.54,.78),(.69,.87),(.69,.93),(.5,.89),(.31,.93),(.31,.87),(.46,.78),(.44,.53),(.07,.63),(.1,.52),(.45,.36),(.46,.15)]
layer=Image.new('RGBA',(size,size)); p=ImageDraw.Draw(layer)
p.polygon([(int(x*size),int(y*size)) for x,y in points],fill=(101,244,204,255))
layer=layer.rotate(28,resample=Image.Resampling.BICUBIC)
shadow=Image.new('RGBA',(size,size)); shadow.paste(layer,(0,25)); shadow=shadow.filter(ImageFilter.GaussianBlur(30))
im=Image.alpha_composite(im.convert('RGBA'),shadow)
im=Image.alpha_composite(im,layer).convert('RGB');im.save(dest/'AppIcon.png')
(dest/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
(root/'SmartPlane/Assets.xcassets/Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
