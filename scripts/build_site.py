import os
# Generates docs/*.html and CHANGELOG.md. Usage: python3 scripts/build_site.py
# To release: add an entry at the top of CHANGELOG below, then run this script.
import pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = str(ROOT / "docs")

# (version, date, {section: [items]}) — newest first
CHANGELOG = [
 ("0.2.0", "2026-11-01", {
   "Added": ["Notification Center widgets: <b>Battery</b> (small, medium) with a state-of-charge ring and your other values, and <b>Values</b> (small, medium, large) mirroring your Displays list. See <a href=\"widgets.html\">Widgets</a>."],
   "Changed": ["The app is now built together with an embedded widget extension. Rebuild with <code>./scripts/bundle.sh</code>."],
 }),
 ("0.1.1", "2026-10-30", {
   "Added": ["Setting “Always show Dock icon” (General). The Dock icon is now visible by default, even when no display targets the Dock. Turn it off for a pure menu bar app."],
   "Fixed": ["Pasting (and copying, cutting, select all, undo) did not work in text fields such as the access token, because the app had no Edit menu."],
 }),
 ("0.1.0", "2026-10-26", {
   "Added": ["Menu bar, Dock icon and floating window displays for any VRM value.",
             "Live streaming over the VRM MQTT broker, plus polling.",
             "24-hour history chart with min, max and average on hover.",
             "Floating windows with four materials, three layouts, typefaces, accent colours and more.",
             "Access token and email/password sign-in, stored in the Keychain.",
             "Launch at login and a configurable refresh interval."],
 }),
]

REPO = "https://github.com/svenwal/VRM-Toolbar"

def head(title, desc, depth_prefix=""):
    return f'''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<meta name="theme-color" content="#080d1c">
<link rel="icon" href="assets/favicon.png">
<link rel="stylesheet" href="assets/style.css">
</head><body>'''

def top(active):
    def a(href, label, key, cls=""):
        on = " on" if key == active else ""
        return f'<a class="{cls}{on}" href="{href}">{label}</a>'
    return f'''<header class="topbar glass">
<a class="brand" href="index.html"><img src="assets/icon.png" alt="">VRM Toolbar</a>
<nav>{a("index.html","Home","home","hide-sm")}{a("getting-started.html","Docs","docs")}{a("changelog.html","Changelog","changelog")}{a(REPO,"GitHub","gh")}</nav>
</header>'''

FOOT = f'''<footer><span>VRM Toolbar is an independent open-source project. Not affiliated with or endorsed by Victron Energy. “Victron”, “VRM” and “Cerbo GX” are trademarks of their respective owners.</span>
<span><a href="changelog.html">Changelog</a> · <a href="{REPO}">Source on GitHub</a></span></footer></body></html>'''

PAGES = [
 ("getting-started", "Getting started", "🚀"),
 ("account", "Account & access token", "🔑"),
 ("displays", "Displays", "📊"),
 ("windows", "Floating windows", "🪟"),
 ("live-and-history", "Live data & history", "⚡"),
 ("widgets", "Widgets", "🧩"),
 ("settings", "General settings", "⚙️"),
 ("build", "Build from source", "🛠"),
 ("troubleshooting", "Troubleshooting & privacy", "🩺"),
]

def doc(slug, title, lede, body):
    i = [p[0] for p in PAGES].index(slug)
    side = '<h5>Documentation</h5>' + "".join(
        f'<a class="{"on" if s == slug else ""}" href="{s}.html"><span>{e}</span>{t}</a>' for s, t, e in PAGES)
    prev = f'<a href="{PAGES[i-1][0]}.html">← {PAGES[i-1][1]}</a>' if i > 0 else '<span></span>'
    nxt = f'<a href="{PAGES[i+1][0]}.html">{PAGES[i+1][1]} →</a>' if i < len(PAGES)-1 else '<span></span>'
    html = head(f"{title} · VRM Toolbar", lede) + top("docs") + f'''
<div class="docs"><aside class="side glass">{side}</aside>
<main class="doc glass"><h1>{title}</h1><p class="lede">{lede}</p>{body}
<div class="pager">{prev}{nxt}</div></main></div>''' + FOOT
    open(f"{OUT}/{slug}.html", "w").write(html)

doc("getting-started", "Getting started", "From download to your first live battery readout in about five minutes.", '''
<h2>What you need</h2>
<ul><li>A Mac running <b>macOS 14 Sonoma or newer</b>. Liquid Glass styling is used on macOS 26 and falls back to system materials on older versions.</li>
<li>A Victron installation that reports to the <b>VRM portal</b> (a GX device such as a Cerbo GX, or a VRM-connected Venus OS).</li>
<li>A VRM account. An access token is recommended.</li></ul>
<h2>1. Install</h2>
<p>There are no prebuilt releases yet, so build the app yourself. It takes one command and needs the Xcode command line tools:</p>
<pre><code>git clone https://github.com/svenwal/VRM-Toolbar.git
cd VRM-Toolbar
./scripts/bundle.sh
open build/VRMToolbar.app</code></pre>
<p>See <a href="build.html">Build from source</a> for details, including code signing.</p>
<h2>2. Sign in</h2>
<p>On first launch the settings window opens on the <b>Account</b> page. Paste a VRM access token (<a href="account.html">how to create one</a>) and press <b>Sign in</b>. The app reads your installations and starts listening for values.</p>
<h2>3. Add a display</h2>
<ol><li>Open <b>Displays</b> and press <b>Add display</b>.</li>
<li>Choose <b>Show in</b>: Menu bar, Dock icon or Floating window.</li>
<li>Pick a value from the list, for example <i>Battery state of charge</i>. Values marked with ⚡ are streamed live.</li>
<li>Optionally set a label, unit or SF Symbol.</li></ol>
<p>It appears immediately. Add as many as you like, and drag them to reorder.</p>
<div class="note"><b>Tip</b>Add a battery state of charge value to make the whole app react to it. The Overview ring and the animated background shift from green to amber to red as the charge drops.</div>
<h2>Where it lives</h2>
<p>VRM Toolbar is a menu bar app. It keeps a Dock icon by default (switch this off under General), and the Dock tile can show values too. Click the menu bar value for the current readings, <i>Refresh</i>, <i>Settings…</i> and <i>Quit</i>.</p>
''')

doc("account", "Account & access token", "Connect VRM Toolbar to your Victron VRM portal securely.", '''
<h2>Access token (recommended)</h2>
<p>An access token works with two-factor authentication and is required for the live stream.</p>
<ol><li>Sign in at <code>vrm.victronenergy.com</code>.</li>
<li>Open <b>Preferences › Integrations</b>.</li>
<li>Under <b>Access tokens</b>, create a new token and copy it.</li>
<li>In VRM Toolbar choose <b>Account › Access token</b>, paste it and press <b>Sign in</b>.</li></ol>
<h2>Email &amp; password</h2>
<p>The alternative sign-in uses your VRM email and password. It does not work with accounts that have two-factor authentication, and Victron has deprecated password access for its APIs. Use a token when you can.</p>
<h2>Where credentials are stored</h2>
<p>Credentials are saved in your <b>login Keychain</b> under the service <code>world.walther.vrm-toolbar</code>. They are only sent to Victron’s servers. <b>Sign out</b> removes them from the Keychain.</p>
<div class="note"><b>Keychain prompts</b>If macOS asks for your password after every rebuild, the app is signed ad hoc. Sign with a stable identity, see <a href="build.html">Build from source</a>.</div>
<h2>Several installations</h2>
<p>If your account has more than one installation, each display has an <b>Installation</b> picker, so you can mix values from a boat, a camper and a cabin.</p>
''')

doc("displays", "Displays", "A display is one value, shown in the menu bar, the Dock icon or a floating window.", '''
<h2>The Displays page</h2>
<p>The list on the left is grouped by where each display appears: <b>Menu bar</b>, <b>Dock icon</b> and one group per floating window. Groups collapse. Hover a row to reveal move up/down arrows and a delete button, or drag rows to reorder them within their group. The editor on the right changes the selected display.</p>
<h2>Targets</h2>
<table><tr><th>Target</th><th>What you get</th></tr>
<tr><td><b>Menu bar</b></td><td>One status item per display, with an optional SF Symbol in front and the value as text. Dimmed when the data is stale.</td></tr>
<tr><td><b>Dock icon</b></td><td>The Dock tile renders up to three values over an electric-blue badge. The Dock icon is always visible by default; with <i>Always show Dock icon</i> turned off, it appears only while a display uses it.</td></tr>
<tr><td><b>Floating window</b></td><td>A translucent, always-on-top panel with any number of values. See <a href="windows.html">Floating windows</a>.</td></tr></table>
<h2>Options</h2>
<table><tr><th>Option</th><th>Effect</th></tr>
<tr><td>Label</td><td>Overrides the name shown for the value.</td></tr>
<tr><td>Unit</td><td>Replaces the unit VRM reports, for example <code>%</code> for a tank level.</td></tr>
<tr><td>SF Symbol</td><td>Menu bar only. Any SF Symbols name, such as <code>bolt.fill</code> or <code>battery.100</code>.</td></tr>
<tr><td>Hero value</td><td>Floating windows only. Marks the one big value in the Hero layout. Only one per window.</td></tr>
<tr><td>Only show while active</td><td>Hides the display while the value is at or below a threshold. Perfect for shore power or AC input that should vanish when you are unplugged.</td></tr>
<tr><td>Installation</td><td>Which of your installations the value comes from. Shown when you have more than one.</td></tr></table>
<h2>Finding a value</h2>
<p>The list shows every value your installation reports, with its current reading. Use the search field to filter. A ⚡ marks values delivered by the live stream.</p>
<h2>Hover for history</h2>
<p>Hover over a menu bar item or a value in a floating window to open a line chart of the last 24 hours with <b>min</b>, <b>max</b> and <b>average</b>. See <a href="live-and-history.html">Live data &amp; history</a>.</p>
''')

doc("windows", "Floating windows", "Create as many always-on-top panels as you like, each with its own look.", '''
<h2>Managing windows</h2>
<p>Open <b>Windows</b> and press <b>New window</b>. Each window has a name, a visibility toggle and a style. A live preview sits on a colourful backdrop so transparency is easy to judge. Assign values to a window from <b>Displays › Show in › Floating window</b>. Drag a window on the desktop to place it, the position is remembered.</p>
<h2>Style options</h2>
<table><tr><th>Setting</th><th>Choices</th></tr>
<tr><td>Material</td><td><b>Glass</b>, <b>Frosted</b>, <b>Solid</b>, <b>Neon</b></td></tr>
<tr><td>Layout</td><td><b>List</b> (rows), <b>Tiles</b> (grid), <b>Hero</b> (one big value with smaller ones beneath, with a configurable number per row)</td></tr>
<tr><td>Typeface</td><td>Rounded, Standard, Monospaced, Serif</td></tr>
<tr><td>Accent</td><td>Any colour</td></tr>
<tr><td>Text</td><td>Auto, Light, Dark, Accent or a custom colour</td></tr>
<tr><td>Opacity</td><td>10 – 100 %</td></tr>
<tr><td>Size</td><td>70 – 200 %</td></tr>
<tr><td>Corners</td><td>Corner radius 0 – 40</td></tr>
<tr><td>Options</td><td>Show labels, always on top</td></tr></table>
<h2>Context menu</h2>
<p>Right-click a floating window for <b>Settings…</b>, <b>Refresh</b>, <b>Hide This Window</b> and <b>Quit</b>.</p>
<div class="note"><b>Idea</b>Make a small, mostly transparent Neon window with just state of charge and power draw, and park it in a screen corner while you work.</div>
''')

doc("live-and-history", "Live data & history", "Values stream in the moment they change, and every value has a chart behind it.", '''
<h2>Live stream</h2>
<p>With an access token, VRM Toolbar connects to the VRM MQTT broker over secure WebSockets for each installation. Streamed values (⚡ in the value list) update instantly, with no polling delay. If the connection drops, the app reconnects on its own.</p>
<h2>Polling</h2>
<p>The VRM API is polled on a schedule (default every 60 seconds, see <a href="settings.html">General settings</a>). When streaming is active, polling mostly refreshes the list of available values. If you sign in with a password, the app polls only.</p>
<h2>History chart</h2>
<p>Hovering a display opens a chart with the last 24 hours. For values VRM stores history for, the data comes from VRM at 15-minute resolution. For anything else the chart is built from samples collected since the app launched. Min, max and average are shown alongside the current value, and the chart uses the window’s typeface and accent colour.</p>
<h2>Stale data</h2>
<p>If no fresh data arrives for a while, menu bar items are dimmed so you do not mistake an old number for a current one.</p>
''')

doc("widgets", "Widgets", "Glance at your system from Notification Center or the desktop.", '''
<h2>Adding a widget</h2>
<ol><li>Start VRM Toolbar at least once, so macOS discovers its widgets.</li>
<li>Click the clock in the menu bar, scroll down and choose <b>Edit Widgets</b>. On macOS 14+ you can also right-click the desktop.</li>
<li>Search for <b>VRM Toolbar</b>, pick a widget and size, and add it.</li></ol>
<h2>Available widgets</h2>
<table><tr><th>Widget</th><th>Sizes</th><th>Shows</th></tr>
<tr><td><b>Battery</b></td><td>Small, Medium</td><td>A state-of-charge ring in the app’s green, amber and red. The medium size adds up to three of your other values.</td></tr>
<tr><td><b>Values</b></td><td>Small, Medium, Large</td><td>The first 3, 4 or 8 values from your <a href="displays.html">Displays</a>, in the same order as the list, including each display’s label and unit.</td></tr></table>
<p>Both use the dark, glowing look of the app, and the glow follows your charge level.</p>
<h2>How fresh is the data?</h2>
<p>The app hands its current values to the widgets and asks macOS to redraw them, at most about every 30 seconds. macOS decides when a widget is really redrawn, so it can lag behind the live menu bar. The time in the corner of the widget shows when the app last received data, and turns orange when the data is stale.</p>
<p>Widgets only update while VRM Toolbar is running, so enable <a href="settings.html">Launch at login</a>. Without the app, they keep showing the last values.</p>
<h2>Which values appear?</h2>
<p>Widgets use the displays you already set up, no extra configuration. Displays hidden by <i>Only show while active</i> are hidden in widgets too. To change what a widget shows, reorder your displays.</p>
<h2>Under the hood</h2>
<p>Widget extensions are sandboxed and have no network access, so the app writes a small snapshot file into a shared app-group container. Your VRM credentials never leave the app.</p>
<div class="note warn"><b>Self-built app</b>Widgets need the app to be code-signed. Build with an Apple Development identity (see <a href="build.html">Build from source</a>), and keep the app in a fixed place such as Applications.</div>
''')

doc("settings", "General settings", "Refresh interval, launch at login, and Dock behaviour.", '''
<h2>Refresh every</h2>
<p>How often the VRM API is polled: 30 seconds, 1, 2, 5 or 10 minutes. Streamed values update instantly regardless.</p>
<h2>Launch at login</h2>
<p>Registers VRM Toolbar as a login item so your readouts are there when you sit down.</p>
<h2>Always show Dock icon</h2>
<p>On by default: the Dock icon stays visible even if no display targets the Dock. Turn it off to run as a pure menu bar app, in which case the icon appears only while at least one display targets the Dock. Clicking the Dock icon or relaunching the app opens Settings.</p>
<h2>Overview page</h2>
<p>The Overview shows a battery ring, a tile for each display and the time of the last update. Its colour (green above 60 %, amber above 30 %, red below) also tints the animated background across the settings window.</p>
''')

doc("build", "Build from source", "VRM Toolbar is a Swift package with no third-party dependencies.", '''
<h2>Requirements</h2>
<ul><li>macOS 14 or newer</li><li>Xcode 16+ or the matching command line tools (Swift 6 toolchain)</li></ul>
<h2>Build &amp; run</h2>
<pre><code>./scripts/bundle.sh          # release build → build/VRMToolbar.app
open build/VRMToolbar.app</code></pre>
<p>The script builds a release binary, wraps it in an app bundle (bundle id <code>world.walther.vrm-toolbar</code>) and signs it.</p>
<h2>Code signing</h2>
<p>The script picks the first <b>Apple Development</b> identity in your Keychain. Override with:</p>
<pre><code>SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/bundle.sh</code></pre>
<p>Without an identity it falls back to an ad-hoc signature. That works, but macOS will ask for Keychain access again after each rebuild.</p>
<h2>Tests</h2>
<pre><code>swift test</code></pre>
<p>Covers configuration decoding, the VRM client and stats parsing, and the MQTT packet codec.</p>
<h2>Project layout</h2>
<table><tr><th>Folder</th><th>Contents</th></tr>
<tr><td><code>API/</code></td><td>VRM REST client and models</td></tr>
<tr><td><code>Live/</code></td><td>Minimal MQTT-over-WebSocket client and live stream</td></tr>
<tr><td><code>State/</code></td><td>Metric store, display configuration</td></tr>
<tr><td><code>History/</code></td><td>History store and hover chart</td></tr>
<tr><td><code>Targets/</code></td><td>Menu bar, Dock and floating window controllers</td></tr>
<tr><td><code>UI/</code></td><td>Settings window pages and the glass kit</td></tr></table>
<h2>App icon</h2>
<p><code>swift scripts/make_icon.swift</code> redraws <code>Resources/AppIcon.icns</code>.</p>
''')

doc("troubleshooting", "Troubleshooting & privacy", "Common problems, and exactly what the app talks to.", '''
<h2>Troubleshooting</h2>
<h3>“Not signed in” in the menu bar</h3><p>Open Settings › Account and sign in. Check that the token was pasted without extra spaces.</p>
<h3>No values in the list</h3><p>Check that your installation is online in the VRM portal. Press <i>Refresh</i> in the menu bar menu.</p>
<h3>Nothing is live (no ⚡)</h3><p>The live stream needs an access token. Password sign-in only polls.</p>
<h3>Password sign-in fails</h3><p>Accounts with two-factor authentication must use an access token.</p>
<h3>Keychain asks for my password constantly</h3><p>Sign the app with a stable identity, see <a href="build.html">Build from source</a>.</p>
<h3>The widgets are not listed</h3><p>Launch the app once from its final location, then reopen Edit Widgets. If they still do not show up, run <code>pluginkit -a /Applications/VRMToolbar.app/Contents/PlugIns/VRMWidget.appex</code>. Unsigned or ad-hoc signed builds may be rejected.</p>\n<h3>The menu bar item disappeared</h3><p>Crowded menu bars (especially on notched Macs) hide overflow items. Remove other items or shorten labels.</p>
<h2>Privacy</h2>
<ul><li>VRM Toolbar talks only to Victron’s services: the VRM API at <code>vrmapi.victronenergy.com</code> and the VRM MQTT broker at <code>webmqtt*.victronenergy.com</code>.</li>
<li>No analytics, telemetry or third-party servers.</li>
<li>Credentials live in your login Keychain. Display settings are stored locally.</li></ul>
<h2>Trademarks</h2>
<p>This is an independent community project. Victron Energy, VRM and related names are trademarks of Victron Energy B.V.; they are used here only to describe compatibility.</p>
''')

# ---------- Changelog ----------
def changelog():
    md = ["# Changelog", "", "All notable changes to VRM Toolbar. Newest first.", ""]
    body = ""
    for v, d, secs in CHANGELOG:
        md += [f"## {v} - {d}", ""]
        body += f'<h2 id="v{v}">{v} <span style="color:var(--faint);font-weight:500;font-size:16px">· {d}</span></h2>'
        for sec, items in secs.items():
            md += [f"### {sec}"] + [f"- {i}" for i in items] + [""]
            body += f"<h3>{sec}</h3><ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>"
    open(str(ROOT / "CHANGELOG.md"), "w").write("\n".join(md))
    html = head("Changelog · VRM Toolbar", "What changed in each version of VRM Toolbar.") + top("changelog") + f'''
<div class="wrap" style="max-width:820px;margin-top:28px"><main class="doc glass"><h1>Changelog</h1><p class="lede">What changed in each version.</p>{body}</main></div>''' + FOOT
    open(f"{OUT}/changelog.html", "w").write(html)
changelog()

# ---------- Home ----------
FW = lambda cls, tag: f'''<div class="fw {cls}"><span class="tag">{tag}</span><h4>Cabin battery</h4>
<div class="row"><span>State of charge</span><span>87 %</span></div>
<div class="row"><span>Solar yield</span><span>412 W</span></div>
<div class="row"><span>Consumption</span><span>186 W</span></div></div>'''

home = head("VRM Toolbar — your Victron battery, always in sight", "A native Mac menu bar, Dock and floating-window display for your Victron VRM installation. Live values, history charts, Liquid Glass design.") + top("home") + f'''
<div class="wrap">
<section class="hero"><div>
<img class="app-icon" src="assets/icon.png" alt="VRM Toolbar app icon">
<h1>Your Victron system, <em>always in sight.</em></h1>
<p class="lead">VRM Toolbar puts battery charge, solar yield and any other VRM value into your Mac’s menu bar, Dock icon or beautifully styled floating windows. Live, not eventually.</p>
<div class="actions"><a class="btn primary" href="getting-started.html">Get started</a><a class="btn" href="{REPO}">View on GitHub</a></div>
<p style="margin-top:22px"><span class="badge glass"><i></i>Free &amp; open source · macOS 14+ · Native SwiftUI</span></p>
</div>
<div class="stage" aria-hidden="true">
<div class="menubar"><span class="v"><span class="bolt">⚡</span>87%</span><span class="v">☀︎ 412 W</span><span class="v dim">⌁ 186 W</span><span class="spacer"></span><span class="dim">Fri 18:42</span></div>
<div class="overview glass"><div class="ring" id="ring"><svg viewBox="0 0 130 130"><circle class="track" cx="65" cy="65" r="57" pathLength="100"/><circle class="bar" cx="65" cy="65" r="57" pathLength="100"/></svg><b id="pct">87%</b></div>
<div style="position:relative;z-index:1"><h3>Battery</h3><p>Colours across the app follow your charge level.</p><p style="font-size:12.5px;color:var(--faint)">🕒 Updated 18:42:07 · live</p></div></div>
<div class="tiles"><div class="tile glass"><small>Solar yield</small><strong>412 W</strong></div><div class="tile glass"><small>Consumption</small><strong>186 W</strong></div><div class="tile glass"><small>Fresh water</small><strong>64 %</strong></div></div>
</div></section>

<section class="block"><div class="eyebrow">Features</div><h2 class="title">Everything a glance should tell you.</h2>
<p class="sub">Designed like the rest of macOS: translucent, calm and quick to read.</p>
<div class="grid3">
<div class="card glass"><div class="ico">⚡</div><h3>Live streaming</h3><p>Values arrive over VRM’s MQTT broker the moment they change. No waiting for the next poll.</p></div>
<div class="card glass"><div class="ico">📍</div><h3>Everywhere you look</h3><p>Menu bar items, the Dock tile, floating panels and Notification Center widgets.</p></div>
<div class="card glass"><div class="ico">🎨</div><h3>Four materials, three layouts</h3><p>Glass, Frosted, Solid or Neon. List, Tiles or Hero. Your accent, your typeface, your corners.</p></div>
<div class="card glass"><div class="ico">📈</div><h3>Hover for history</h3><p>Hover any value for a 24-hour chart with min, max and average.</p></div>
<div class="card glass"><div class="ico">🫥</div><h3>Show only when relevant</h3><p>Hide shore power when you are unplugged. Displays can disappear below a threshold you choose.</p></div>
<div class="card glass"><div class="ico">🔐</div><h3>Private by design</h3><p>Talks only to Victron. Credentials stay in your Keychain. No telemetry, no dependencies.</p></div>
</div></section>

<section class="block"><div class="eyebrow">Floating windows</div><h2 class="title">Make it look like yours.</h2>
<p class="sub">Create as many windows as you want. Same data, four moods.</p>
<div class="showcase" aria-hidden="true">{FW("glass-m","Glass")}{FW("frosted","Frosted")}{FW("solid","Solid")}{FW("neon","Neon")}</div></section>

<section class="block"><div class="eyebrow">Setup</div><h2 class="title">Up and running in minutes.</h2><br>
<ol class="steps">
<li class="glass"><div><b>Build the app</b><span>Clone the repo and run <code>./scripts/bundle.sh</code>.</span></div></li>
<li class="glass"><div><b>Paste your VRM access token</b><span>Create it under VRM › Preferences › Integrations.</span></div></li>
<li class="glass"><div><b>Pick the values you care about</b><span>Choose a place for each one, and you’re done.</span></div></li>
</ol></section>

<section class="cta glass"><h2>Keep an eye on your power.</h2><p>Open source under your control. Read the docs or grab the code.</p>
<div class="actions" style="display:flex;gap:12px;justify-content:center;flex-wrap:wrap"><a class="btn primary" href="getting-started.html">Read the docs</a><a class="btn" href="{REPO}">Source on GitHub</a></div></section>
</div>
<script>
// Cycle the demo ring through the same green → amber → red thresholds the app uses.
(function () {{
  var ring = document.getElementById("ring"), pct = document.getElementById("pct");
  var levels = [87, 54, 22, 87], i = 0;
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  setInterval(function () {{
    i = (i + 1) % levels.length; var v = levels[i];
    ring.style.setProperty("--p", v);
    ring.style.setProperty("--c", v > 60 ? "var(--good)" : v > 30 ? "var(--warn)" : "var(--bad)");
    pct.textContent = v + "%";
  }}, 3500);
}})();
</script>''' + FOOT
open(f"{OUT}/index.html", "w").write(home)
open(f"{OUT}/.nojekyll", "w").write("")
