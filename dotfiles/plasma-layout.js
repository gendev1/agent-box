// Plasma layout: a thin bar on top, like Omarchy's, and a full-width dock at
// the bottom with the app icons centered. Both are always visible.
// install.sh runs this on every run. It builds the panels only if there is no
// top bar yet, so changes you make by hand in the panel settings are kept;
// only the dock's width and visibility are set each time.

var DEFAULT_LAUNCHERS = [
    "applications:org.kde.dolphin.desktop",
    "applications:kitty.desktop",
    "preferred://browser",
    "applications:dev.zed.Zed.desktop",
    "applications:md.obsidian.Obsidian.desktop",
    "applications:com.spotify.Client.desktop",
    "applications:systemsettings.desktop"
].join(",");

function findDock() {
    return panels().filter(function (p) {
        return p.location == "bottom" && p.widgets("org.kde.plasma.icontasks").length > 0;
    })[0];
}

// Dock: spacer, app icons, spacer. The spacers share the free space, which
// pads the icons equally on both sides.
function buildDock(launchers) {
    var dock = new Panel;
    dock.location = "bottom";
    dock.height = 56;
    dock.floating = false;
    dock.alignment = "center";
    dock.hiding = "none";
    dock.addWidget("org.kde.plasma.panelspacer");
    var tasks = dock.addWidget("org.kde.plasma.icontasks");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", launchers);
    tasks.writeConfig("fill", false); // only as wide as its icons
    dock.addWidget("org.kde.plasma.panelspacer");
    return dock;
}

var hasTopBar = panels().some(function (p) { return p.location == "top"; });
if (!hasTopBar) {
    panels().forEach(function (p) { p.remove(); });

    // Top bar: launcher and desktops on the left, clock in the middle, tray on the right.
    var bar = new Panel;
    bar.location = "top";
    bar.height = 30;
    bar.floating = false;
    bar.lengthMode = "fill";
    bar.addWidget("org.kde.plasma.kickoff");
    var pager = bar.addWidget("org.kde.plasma.pager");
    pager.currentConfigGroup = ["General"];
    pager.writeConfig("displayedText", "Number");
    pager.writeConfig("showWindowIcons", false);
    bar.addWidget("org.kde.plasma.panelspacer");
    var clock = bar.addWidget("org.kde.plasma.digitalclock");
    clock.currentConfigGroup = ["Appearance"];
    clock.writeConfig("showDate", true);
    clock.writeConfig("dateDisplayFormat", 1); // beside the time
    bar.addWidget("org.kde.plasma.panelspacer");
    bar.addWidget("org.kde.plasma.systemtray");

    buildDock(DEFAULT_LAUNCHERS);
}

// A dock from before the spacers were added: rebuild it, keeping its icons.
var dock = findDock();
if (dock && dock.widgets("org.kde.plasma.panelspacer").length == 0) {
    var tasks = dock.widgets("org.kde.plasma.icontasks")[0];
    tasks.currentConfigGroup = ["General"];
    // Plasma can return an empty list here; fall back to the standard icons.
    var launchers = String(tasks.readConfig("launchers", "")) || DEFAULT_LAUNCHERS;
    dock.remove();
    dock = buildDock(launchers);
}

// Full width, flush with the screen edge, and always visible; windows stop
// at its edge.
if (dock) {
    dock.lengthMode = "fill";
    dock.floating = false;
    dock.hiding = "none";
}
