class_name Scene01UILayoutMetrics
extends RefCounted

const COMPACT_BREAKPOINT := 1600.0
const WIDE_BREAKPOINT := 1920.0

const EDGE_MARGIN := 16.0
const CONTENT_TOP := 82.0
const CONTENT_BOTTOM_MARGIN := 16.0
const OPERATIONS_PANEL_HEIGHT := 218.0
const RIGHT_RAIL_SECTION_GAP := 8.0

const REFERENCE_VIEWPORT_WIDTH := 2264.0
const REFERENCE_LEFT_RAIL_WIDTH := 300.0
const LEFT_RAIL_WIDTH_PROPORTION := REFERENCE_LEFT_RAIL_WIDTH / REFERENCE_VIEWPORT_WIDTH
const LEFT_RAIL_MIN_WIDTH := 296.0
const LEFT_RAIL_COLLAPSED_WIDTH := 44.0

const PROGRAM_COLLAPSED_WIDTH := 56.0
const PROGRAM_NARROW_WIDTH := 360.0
const PROGRAM_COMPACT_WIDTH := 400.0
const PROGRAM_WIDE_WIDTH := 460.0


static func left_rail_width(viewport_width: float) -> float:
	return maxf(roundf(viewport_width * LEFT_RAIL_WIDTH_PROPORTION), LEFT_RAIL_MIN_WIDTH)


static func left_sidebar_max_height(viewport_height: float) -> float:
	return maxf(viewport_height - CONTENT_TOP - CONTENT_BOTTOM_MARGIN, 0.0)


static func program_rail_width(viewport_width: float) -> float:
	return PROGRAM_WIDE_WIDTH if viewport_width >= WIDE_BREAKPOINT else (
		PROGRAM_COMPACT_WIDTH if viewport_width >= COMPACT_BREAKPOINT else PROGRAM_NARROW_WIDTH
	)


static func program_rail_top() -> float:
	return CONTENT_TOP + OPERATIONS_PANEL_HEIGHT + RIGHT_RAIL_SECTION_GAP
