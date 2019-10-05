spider-parts: assets/spine/spider.svg
	python -m inkscape_split --dpi 180 assets/spine/spider.svg

assets/graphics/spider.atlas assets/graphics/spider.json: assets/spine/spider.spine spider-parts
	~/Applications/Spine/Spine.sh -i $< -e assets/spine/export.json -o assets/graphics

spine-assets: assets/graphics/spider.atlas assets/graphics/spider.json
