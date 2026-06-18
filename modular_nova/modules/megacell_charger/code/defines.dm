/// Wallframe mount mode: standard APC construction.
#define WALLFRAME_APC 0
/// Wallframe mount mode: megacell charger field-mod frame.
#define WALLFRAME_MEGACELL_CHARGER 1

/// Mounted APC-style shell, no terminal yet.
#define MEGACELL_CHARGER_FRAME 0
/// Underfloor power terminal installed.
#define MEGACELL_CHARGER_TERMINAL 1
/// Iron and capacitor inserted, ready to weld.
#define MEGACELL_CHARGER_PARTS 2
/// Welded and operational.
#define MEGACELL_CHARGER_COMPLETE 3

#define MEGACELL_CHARGER_PIXEL_OFFSET 26

/// Baseline megacell tiers only — matches big_cell_charger.dmi cell overlays (cellbig, hcellbig, scellbig, hpcellbig).
GLOBAL_LIST_INIT(megacell_charger_allowed_batteries, typecacheof(list(
	/obj/item/stock_parts/power_store/battery,
	/obj/item/stock_parts/power_store/battery/empty,
	/obj/item/stock_parts/power_store/battery/upgraded,
	/obj/item/stock_parts/power_store/battery/high,
	/obj/item/stock_parts/power_store/battery/high/empty,
	/obj/item/stock_parts/power_store/battery/super,
	/obj/item/stock_parts/power_store/battery/super/empty,
	/obj/item/stock_parts/power_store/battery/hyper,
	/obj/item/stock_parts/power_store/battery/hyper/empty,
), only_root_path = TRUE))
