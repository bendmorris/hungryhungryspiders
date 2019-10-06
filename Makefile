spider-parts: assets/spine/spider.svg
	python -m inkscape_split --dpi 180 assets/spine/spider.svg

assets/graphics/spider.atlas assets/graphics/spider.json: assets/spine/spider.spine spider-parts
	~/Applications/Spine/Spine.sh -i $< -e assets/spine/export.json -o assets/graphics

spine-assets: assets/graphics/spider.atlas assets/graphics/spider.json

assets/fonts/octobercrow.72.fnt: assets/fonts/octobercrow.ttf
	python -m bmfg $< --size 72 --padding 4 --max-texture-size 2048 --border 8 --border-color 202020ff --char-spacing 1 --antialiasing -o assets/fonts/octobercrow

%.png: %.svg
	inkscape --without-gui --export-png=$@ --export-dpi=96 $<

%.ogg: %.wav
	rm -f $@
	ffmpeg -i $< -c libvorbis -q 1 -b:a 8k $@

%.wav: %.xm
	xmp $< -a 2 -o $@
