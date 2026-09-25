class_name Scene01UILayoutMetrics
extends RefCounted

const COMPACT_BREAKPOINT := 1600.0
const WIDE_BREAKPOINT := 1920.0

const EDGE_MARGIN := 16.0
const CONTENT_TOP := 82.0
const CONTENT_BOTTOM_MARGIN := 16.0

const LEFT_NARROW_WIDTH := 320.0
const LEFT_COMPACT_WIDTH := 336.0
const LEFT_WIDE_WIDTH := 352.0
const LEFT_SIDEBAR_VERTICAL_PADDING := 16.0

const PROGRAM_COLLAPSED_WIDTH := 56.0
const PROGRAM_NARROW_WIDTH := 360.0
const PROGRAM_COMPACT_WIDTH := 400.0
const PROGRAM_WIDE_WIDTH := 460.0


static func left_rail_width(viewport_width: float) -> float:
	return LEFT_WIDE_WIDTH if viewport_width >= WIDE_BREAKPOINT else (
		LEFT_COMPACT_WIDTH if viewport_width >= COMPACT_BREAKPOINT else LEFT_NARROW_WIDTH
	)


static func left_sidebar_max_height(viewport_height: float) -> float:
	return maxf(viewport_height - CONTENT_TOP - CONTENT_BOTTOM_MARGIN, 0.0)


static func program_rail_width(viewport_width: float) -> float:
	return PROGRAM_WIDE_WIDTH if viewport_width >= WIDE_BREAKPOINT else (
		PROGRAM_COMPACT_WIDTH if viewport_width >= COMPACT_BREAKPOINT else PROGRAM_NARROW_WIDTH
	)
