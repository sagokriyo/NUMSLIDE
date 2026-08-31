## A single theme, authored as a .tres resource.
##
## This is the *contract* every theme fills. Adding a new theme is a new .tres
## file in data/themes/ with these fields set — no code changes anywhere.
## ThemeManager loads one of these as the active theme and exposes its values.
class_name ThemeData
extends Resource

## "minimal" | "aesthetic" | "fun" | "premium" | "shop" — a loose authoring
## label. The picker groups by ENTITLEMENT tier (Free / Shop / Premium) via
## Entitlements, NOT this field; only "shop" here still has to agree with
## Entitlements.SHOP_THEMES (checked in tests/test_themes.gd).
@export var display_name: String = "Untitled"
@export_enum("minimal", "aesthetic", "fun", "premium", "shop") var category: String = "minimal"

## True for palettes designed to be colorblind-safe / high-contrast friendly.
@export var colorblind_safe: bool = false

@export_group("Surfaces")
@export var bg: Color = Color(0.96, 0.96, 0.98)            ## App background
@export var surface: Color = Color(1, 1, 1)                ## Panels / cards
@export var surface_alt: Color = Color(0.92, 0.92, 0.95)   ## Secondary panels
@export var accent: Color = Color(0.22, 0.45, 0.92)        ## Primary accent
@export var accent_soft: Color = Color(0.55, 0.70, 1.0)    ## Hover / soft accent

@export_group("Text")
@export var text: Color = Color(0.12, 0.12, 0.12)
@export var text_muted: Color = Color(0.40, 0.40, 0.45)
@export var text_on_accent: Color = Color(1, 1, 1)

@export_group("Grid")
@export var cell_empty: Color = Color(1, 1, 1)
@export var cell_given: Color = Color(0.90, 0.90, 0.90)
@export var cell_selected: Color = Color(0.55, 0.78, 1.0)
@export var cell_peer: Color = Color(0.90, 0.94, 1.0)          ## Row/col/box peer
@export var cell_same_number: Color = Color(0.75, 0.86, 1.0)
@export var cell_error: Color = Color(1.0, 0.7, 0.7)
@export var cell_correct: Color = Color(0.82, 0.95, 0.82)
@export var cell_text: Color = Color(0.15, 0.30, 0.55)        ## Player-entered
@export var cell_given_text: Color = Color(0.15, 0.15, 0.15)  ## Locked clues
@export var border_thin: Color = Color(0.7, 0.7, 0.7)
@export var border_box: Color = Color(0, 0, 0)               ## 3x3 box / outer

@export_group("Effects")
@export var enable_glow: bool = false
@export var glow_color: Color = Color(0.4, 0.7, 1.0, 0.5)
@export_range(0.0, 1.0) var shadow_strength: float = 0.25
## Which BackgroundFX preset pairs with this theme (Phase 5.2).
@export var background_id: String = "gradient"
## Second gradient stop for background_id == "gradient".
@export var bg_gradient_bottom: Color = Color(0.90, 0.92, 0.98)
## Live gameplay "feel" profile. Drives ambient particle density, the tile pulse
## and how the board answers a combo:
##   calm    — the quiet premium default (authored density, no pulse, no reaction)
##   playful — colored merge sparks + juicier spawn squash + a combo jolt
##   arcade  — densest field (1.40x), fast tile flash from 256, biggest jolt
##   living  — 1.20x field, a slow deep breath on 512+ tiles, a swell on combos
##   vivid   — 1.28x field, the living breath plus playful's juicier spawns
## `living` and `vivid` were declared here long before anything read them: every
## branch tested only for "arcade" and "playful", so eighteen themes ran as calm.
@export_enum("calm", "playful", "arcade", "living", "vivid") var fx_style: String = "calm"

## Premium board/tile treatment. "plain" is the standard glass board; the others
## add a metallic / crystalline / molten frame + a matching tile sheen so a theme's
## board reflects its name (gold leaf, brushed silver, frosted crystal, lava …).
@export_enum("plain", "gold", "silver", "crystal", "molten", "deep",
	"jade", "phantom", "shadow", "desert", "toxic", "rose", "emerald", "ruby",
	"biolum", "amethyst", "bronze", "matrix",
	"rgb", "void", "astral", "ink", "plasma",
	"nova", "comet", "atlas",
	# Boards authored so no theme has to fall back to the generic accent->gold ramp
	# (which always ended gold however cool the palette was) or share another
	# theme's tiles. See ThemeManager._LUXE_RAMPS for what each one paints.
	"aurora", "dawn", "firefly", "stellar", "storm", "press", "sand", "onyx",
	"origami", "hoarfrost", "foliage", "bloodmoon", "coral", "koi", "duskbloom",
	"lantern", "lacquer", "nebula", "vapor",
	"cel", "crt", "confect", "bigtop", "pastelpop",
	# The 2026-08 additions, each with its own ramp + accent in ThemeManager.
	"honey", "diamond", "morpho", "plume",
	# The ten premium worlds of 2026-08-27 (docs/themes/ten-premium-themes.md).
	"marble", "noir", "mono", "wash", "bismuth", "azure", "lagoon",
	"savanna", "redwood") var board_style: String = "plain"

## THERE IS NO TYPOGRAPHY HERE, and that is deliberate. Two font slots used to
## live in this resource: a `number_font` that re-lettered the TILE NUMERALS
## (Circuit Pulse, Arcade, Neon Blue and Vaporwave dealt their boards in a pixel
## face) and a `heading_font` that re-lettered the HEADINGS (Cinzel on Sanctum,
## Baloo on Carnival, Caveat on Paper), so the app's type changed with every
## theme the player browsed. Both were removed: a theme changes colour, material
## and motion, never the app's voice — Malam Poek is the display face under every
## palette. Fonts are sealed once in ThemeManager._load_fonts; test_theme_visuals
## fails if a Font-typed export grows back on this class.

@export_group("Audio")
## Which ambience loop pairs with this theme (Phase 5.2). Empty = silence.
@export var ambience_id: String = ""
