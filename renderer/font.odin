package renderer

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Glyph :: struct {
	uv:       Vec4,
	width:    f32,
	height:   f32,
	xOffset:  f32,
	yOffset:  f32,
	xAdvance: f32,
}

Font :: struct {
	atlas:    Texture,
	glyphMap: map[rune]Glyph,
	size:     f32,
	lHeight:  f32,
}

load_font :: proc(path: string) -> Font {
	data, ok := os.read_entire_file(path)
	if !ok {
		panic("Failed to read font file")
	}

	text := string(data)
	lines := strings.split_lines(text)

	font := Font{}
	font.glyphMap = make(map[rune]Glyph)

	scaleW: f32 = 1
	scaleH: f32 = 1

	atlas_file := ""

	for line in lines {
		if strings.has_prefix(line, "info") {
			fields := strings.split(line, " ")

			for f in fields {
				if strings.has_prefix(f, "size=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "size="))
					font.size = f32(value)
				}
			}
		}
		if strings.has_prefix(line, "common") {
			fields := strings.split(line, " ")

			for f in fields {
				if strings.has_prefix(
					f,
					"scaleW=",
				) {value, _ := strconv.parse_int(strings.trim_prefix(f, "scaleW="))
					scaleW = f32(value)
				}
				if strings.has_prefix(f, "scaleH=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "scaleH="))
					scaleH = f32(value)
				}
				if strings.has_prefix(f, "lineHeight=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "lineHeight="))
					font.lHeight = f32(value)
				}
			}
		}

		if strings.has_prefix(line, "file=") {
			name := strings.trim_prefix(line, "file=")
			name = strings.trim(name, "\"")
			atlas_file = name
		}

		if strings.has_prefix(line, "char ") {
			fields := strings.split(line, " ")

			id: int
			x: f32
			y: f32
			w: f32
			h: f32
			xoff: f32
			yoff: f32
			xAdvance: f32

			for f in fields {
				if strings.has_prefix(f, "id=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "id="))
					id = int(value)
				}
				if strings.has_prefix(f, "x=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "x="))
					x = f32(value)
				}
				if strings.has_prefix(f, "y=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "y="))
					y = f32(value)
				}
				if strings.has_prefix(f, "width=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "width="))
					w = f32(value)
				}
				if strings.has_prefix(f, "height=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "height="))
					h = f32(value)
				}
				if strings.has_prefix(f, "xoffset=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "xoffset="))
					xoff = f32(value)
				}
				if strings.has_prefix(f, "yoffset=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "yoffset="))
					yoff = f32(value)
				}
				if strings.has_prefix(f, "xadvance=") {
					value, _ := strconv.parse_int(strings.trim_prefix(f, "xadvance="))
					xAdvance = f32(value)
				}
			}

			u0 := x / scaleW
			v0 := 1 - y / scaleH
			u1 := (x + w) / scaleW
			v1 := 1 - (y + h) / scaleH

			glyph := Glyph {
				uv       = Vec4{u0, v0, u1, v1},
				width    = w,
				height   = h,
				xOffset  = xoff,
				yOffset  = yoff,
				xAdvance = xAdvance,
			}

			font.glyphMap[rune(id)] = glyph
		}
	}

	atlas_path := strings.concatenate({"renderer/fonts/", atlas_file})
	load_texture(atlas_path, &font.atlas)

	return font
}

cleanup_font :: proc(font: ^Font) {
	cleanup_texture(&font.atlas)
}
