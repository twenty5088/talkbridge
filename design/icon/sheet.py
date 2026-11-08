from PIL import Image, ImageDraw, ImageFont
imgs=[Image.open(f"icon_{v}.png") for v in "ABC"]
pad=40; s=360
sheet=Image.new("RGB",(pad+3*(s+pad), s+2*pad+40),(245,245,247))
d=ImageDraw.Draw(sheet); f=ImageFont.truetype("arial.ttf",28)
mask=Image.new("L",(s,s),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,s-1,s-1],radius=int(s*0.225),fill=255)
for i,im in enumerate(imgs):
    x=pad+i*(s+pad)
    sheet.paste(im.resize((s,s),Image.LANCZOS),(x,pad),mask)
    d.text((x+s//2-8,pad+s+8),"ABC"[i],fill=(60,60,60),font=f)
sheet.save("preview.png")
