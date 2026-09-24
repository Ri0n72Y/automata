class_name Scene01UILayoutMetrics
extends RefCounted

const COMPACT_BREAKPOINT := 1600.0
const WIDE_BREAKPOINT := 1920.0

const EDGE_MARGIN := 16.0
const CONTENT_TOP := 82.0
const CONTENT_BOTTOM_MARGIN := 16.0
const PANEL_GAP := 12.0

const LEFT_STATUS_HEIGHT := 198.0
const LEFT_AUX_TOP := CONTENT_TOP + LEFT_STATUS_HEIGHT + PANEL_GAP
const TUTORIAL_TARGET_HEIGHT := 308.0

const LEFT_NARROW_WIDTH := 300.0
const LEFT_COMPACT_WIDTH := 320.0
const LEFT_WIDE_WIDTH := 360.0

const PROGRAM_COLLAPSED_WIDTH := 52.0
const PROGRAM_NARROW_WIDTH := 360.0
const PROGRAM_COMPACT_WIDTH := 400.0
const PROGRAM_WIDE_WIDTH := 460.0


static func left_rail_width(viewport_width: float) -> float:
	return LEFT_WIDE_WIDTH if viewport_width >= WIDE_BREAKPOINT else (
		LEFT_COMPACT_WIDTH if viewport_width >= COMPACT_BREAKPOINT else LEFT_NARROW_WIDTH
	)


static func program_rail_width(viewport_width: float) -> float:
	return PROGRAM_WIDE_WIDTH if viewport_width >= WIDE_BREAKPOINT else (
		PROGRAM_COMPACT_WIDTH if viewport_width >= COMPACT_BREAKPOINT else PROGRAM_NARROW_WIDTH
	)


static func available_height(viewport_height: float, top: float) -> float:
	return maxf(0.0, viewport_height - CONTENT_BOTTOM_MARGIN - top)


static func clamped_panel_height(
	viewport_height: float,
	top: float,
	desired_height: float,
	minimum_height: float
) -> float:
	return maxf(minimum_height, minf(desired_height, available_height(viewport_height, top)))
