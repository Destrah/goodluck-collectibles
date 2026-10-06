"""Build deterministic original comic test artwork and a FiveM sample manifest.
Run with Python + Pillow. Never edits the installed catalog or existing artwork.
"""
from pathlib import Path
import colorsys
import json
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'public/img/sample'
ART.mkdir(parents=True, exist_ok=True)
W, H = 420, 588
names = ['Solar', 'Lunar', 'Neon', 'Crimson', 'Azure', 'Amber', 'Violet', 'Silver', 'Emerald', 'Obsidian']
roles = ['Sentinel', 'Courier', 'Warden', 'Pilot', 'Medic', 'Scout', 'Guardian', 'Engineer', 'Ranger', 'Oracle']
types = ['police', 'civilian', 'legal', 'vehicle', 'medical', 'criminal', 'structure', 'farmer', 'location', 'civilian']
effects = ['outline-rainbow','outline-gold','outline-silver','foil-rainbow','foil-prism','foil-etched','foil-cosmos','foil-galaxy','foil-flame','foil-flame-v2','foil-flame-hybrid','foil-flame-anime','foil-flame-smoky','foil-electric','foil-water','foil-smoke','foil-frost']
holos = ['none','rainbow','prism','cosmos','reverse','etched','aurora','oilslick']
layouts = ['classic','full-art','illustration','dark-borderless']
tiers = ['common','common','uncommon','rare','rare','ultra_rare','ultra_rare','legendary']
weights = [120,55,35,24,12,8,4,1]
cards=[]
for archetype in range(10):
    mask=Image.new('L',(W,H));d=ImageDraw.Draw(mask)
    d.polygon([(167,260),(110,304),(78,440),(123,463),(158,357),(148,535),(272,535),(262,357),(299,463),(343,440),(310,304),(253,260)],fill=255)
    d.ellipse((145,149,275,283),fill=255)
    if archetype % 3 == 1:
        d.polygon([(147,182),(153,121),(192,155),(228,155),(268,121),(272,185)],fill=255)
    elif archetype % 3 == 2:
        d.rectangle((148,167,273,250),fill=255)
    outline=ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(15)),mask.filter(ImageFilter.MinFilter(9)))
    accent=Image.new('L',(W,H));ImageDraw.Draw(accent).polygon([(184,325),(210,299),(236,325),(210,352)],fill=255)
    for label,m in [('subject',mask),('outline',outline),('accent',accent)]:
        rgba=Image.new('RGBA',(W,H),'white');rgba.putalpha(m);rgba.save(ART/f'mask-{archetype}-{label}.png')
    mask.convert('RGB').save(ART/f'mask-{archetype}-luminance.png')
    ImageChops.invert(mask).convert('RGB').save(ART/f'mask-{archetype}-inverted.png')
    for color in range(10):
        number=archetype*10+color+1
        rgb=tuple(round(c*255) for c in colorsys.hsv_to_rgb(color/10,.74,.92))
        accent_hex='#'+''.join(f'{c:02x}' for c in rgb)
        image=Image.new('RGB',(W,H),'#101626');draw=ImageDraw.Draw(image)
        for y in range(H):
            draw.line((0,y,W,y),fill=tuple(int((c*.32)*(1-y/H)+12*y/H) for c in rgb))
        draw.ellipse((-120,-20,500,520),fill=tuple(int(c*.20) for c in rgb),outline=rgb,width=2)
        for k in range(18):
            x=(k*67+color*23)%W;height=35+(k*43+number*11)%160
            draw.rectangle((x,H-height,x+35,H),fill='#080e1d')
            for yy in range(H-height+10,H-8,19):draw.rectangle((x+8,yy,x+12,yy+4),fill=rgb)
        for k in range(45):
            x=(k*79+number*17)%W;y=(k*109+number*31)%H
            draw.ellipse((x,y,x+2,y+2),fill=rgb)
        subject=Image.new('RGB',(W,H),rgb);sd=ImageDraw.Draw(subject)
        sd.polygon([(165,264),(210,316),(255,264),(253,411),(167,411)],fill='#182438')
        sd.line((210,359,210,535),fill='#070c17',width=12)
        sd.rectangle((158,401,262,421),fill='#101725')
        sd.ellipse((145,149,275,283),fill='#172238',outline=rgb,width=8)
        sd.rounded_rectangle((159,195,260,222),radius=8,fill='#d7f9ff')
        sd.line((177,232,244,232),fill=rgb,width=3)
        sd.polygon([(184,325),(210,299),(236,325),(210,352)],fill='#fff5a6')
        image.paste(subject,(0,0),mask)
        image.save(ART/f'hero-{number:03d}.png',optimize=True)
        card_id=f'sample-{number:03d}'
        variants=[]
        for v in range(8):
            layers=[]
            if v>=2:
                mode=effects[(number+v)%len(effects)]
                mask_kind=['subject','outline','accent','luminance','inverted'][((number+v)%5)]
                layers.append({'id':f'{card_id}-p{v}-mask','name':f'{mask_kind.title()} {mode}',
                    'image':f'/img/sample/mask-{archetype}-{mask_kind}.png','mode':mode,'maskOnly':True,
                    'maskSource':'luminance' if mask_kind=='luminance' else 'luminance-invert' if mask_kind=='inverted' else 'alpha',
                    'strength':35+(number*7+v*13)%61,'foilA':accent_hex,'foilB':'#59e7ff','foilC':'#ffe66d'})
                if v==7:
                    layers.append({'id':f'{card_id}-p{v}-outline','name':'Chase outline','image':f'/img/sample/mask-{archetype}-outline.png','mode':'outline-gold','maskOnly':True,'maskSource':'alpha','strength':85,'foilA':'#ffd23c','foilB':'#ff54bd','foilC':'#fff6d7'})
            variants.append({'id':f'{card_id}-print-{v+1}','name':['Standard','Rainbow Holo','Prism Variant','Cosmos Rare','Reverse Rare','Etched Ultra','Aurora Ultra','Oil Slick Chase'][v],
                'rarityKey':tiers[v],'rarity':tiers[v].replace('_',' ').title(),'chanceWeight':weights[v]+number%5,
                'layout':layouts[v%4],'holo':holos[v],'holoStrength':25+(number*3+v*9)%71,
                'imagePositionX':45+number%11,'imagePositionY':46+v%9,'imageZoom':100+(number+v)%16,
                'accent':accent_hex,'foilA':accent_hex,'foilB':'#59e7ff','foilC':'#ffe66d','subjectLayers':layers})
        cards.append({'id':card_id,'title':f'{names[color]} {roles[archetype]}','subtitle':'Meta Comics Sample Universe',
            'type':types[archetype],'hp':60+(number%15)*10,'chanceWeight':[5,15,30,60,100][number%5],
            'image':f'/img/sample/hero-{number:03d}.png','accent':accent_hex,'foilA':accent_hex,'foilB':'#59e7ff','foilC':'#ffe66d',
            'setName':'Sample','cardNumber':f'{number:03d}','setTotal':'100',
            'description':f'Original test character {number:03d}. Eight independent prints exercise layouts, weighted pulls and aligned masks.',
            'attacks':[{'name':'Signal Strike','cost':1+number%3,'damage':10+(number%8)*10,'text':'A sample move for UI testing.'}],
            'sampleSeedVersion':1,'variants':variants})
target=ROOT/'fivem/data/sample-cards.json'
target.write_text(json.dumps({'version':1,'set':{'id':'sample','name':'Sample','code':'SMP','description':'100 original test characters / 800 prints','cardIds':[c['id'] for c in cards]},'cards':cards},separators=(',',':')),encoding='utf-8')
print(f'Generated {len(cards)} base cards, {sum(len(c["variants"]) for c in cards)} prints, 150 PNG assets; existing catalogs untouched.')
