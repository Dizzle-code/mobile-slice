// Draws the app's pixel icons, detects the visitor's system and links the matching file of the newest release.
"use strict";

const REPO = "Dizzle-code/mobile-slice";
const RELEASES = `https://github.com/${REPO}/releases`;
// Used when the GitHub API is unreachable or rate limited (60 requests per hour and IP).
const FALLBACK = {
  tag: "v1.1.0",
  prerelease: true,
  files: {
    windows: "Mobile-Slice-1.1.0-Windows-Setup.exe",
    macos: "Mobile-Slice-1.1.0-macOS-AppleSilicon.dmg",
    android: "Mobile-Slice-1.1.0-Android-arm64.apk",
  },
};
const PATTERNS = {
  windows: /windows.*\.exe$/i,
  macos: /macos.*\.dmg$/i,
  android: /\.apk$/i,
};
const NAMES = { windows: "Windows", macos: "macOS", android: "Android" };

const COLORS = { text: "#F2EFE6", accent: "#FF8A3D", green: "#5BD46A", yellow: "#FFD447" };

// Same format as app/lib/ui/pixel_icons.dart: "#" main color, "+" second color, 16×16.
const GLYPHS = {
  cube: ["................", ".......##.......", ".....##++##.....", "...##++++++##...", ".##++++++++++##.", ".#.##++++++##.#.", ".#...##++##...#.", ".#.....##.....#.", ".#......#.....#.", ".#......#.....#.", ".#......#.....#.", ".##.....#....##.", "...##...#..##...", ".....##.#.##....", ".......##......."],
  download: ["................", "......####......", "......#++#......", "......#++#......", "......#++#......", "...####++####...", "....#++++++#....", ".....#++++#.....", "......#++#......", ".......##.......", ".##..........##.", ".##############.", ".##############."],
  folder: ["................", "................", ".#####..........", ".#+++#########..", ".#+++++++++++#..", ".##############.", ".#++++++++++++#.", ".#++++++++++++#.", ".#++++++++++++#.", ".#++++++++++++#.", ".#++++++++++++#.", ".#++++++++++++#.", ".##############."],
  layers: ["................", "...##########...", "..#++++++++++#..", "...##########...", "................", "...##########...", "..#++++++++++#..", "...##########...", "................", "...##########...", "..#++++++++++#..", "...##########..."],
  upload: [".......##.......", "......####......", ".....######.....", "....########....", "...##.####.##...", "......####......", "......####......", "......####......", "......####......", "................", ".##..........##.", ".##..........##.", ".##++++++++++##.", ".##############."],
  windows: ["................", "................", "..+++++.+++++++.", "..+++++.+++++++.", "..+++++.+++++++.", "..+++++.+++++++.", "..+++++.+++++++.", "................", "..+++++.+++++++.", "..+++++.+++++++.", "..+++++.+++++++.", "..+++++.+++++++.", "..+++++.+++++++.", "................"],
  apple: ["................", ".........++.....", "........++......", "........+.......", "...####..####...", "..############..", ".############...", ".###########....", ".###########....", ".###########....", ".############...", "..############..", "..############..", "...####..####...", "................"],
  android: ["................", "....+......+....", ".....+....+.....", "....++++++++....", "...++#++++#++...", "...++++++++++...", "................", ".+.##########.+.", ".+.##########.+.", ".+.##########.+.", ".+.##########.+.", "...##########...", ".....##..##.....", ".....##..##....."],
};

function drawIcons() {
  for (const canvas of document.querySelectorAll("canvas[data-glyph]")) {
    const rows = GLYPHS[canvas.dataset.glyph];
    if (!rows) continue;
    const scale = Number(canvas.dataset.scale || 2);
    canvas.width = canvas.height = 16;
    canvas.style.width = canvas.style.height = `${16 * scale}px`;
    const ctx = canvas.getContext("2d");
    const tones = { "#": canvas.dataset.ink || COLORS.text, "+": canvas.dataset.second || COLORS.accent };
    rows.forEach((row, y) => {
      [...row].forEach((cell, x) => {
        if (!tones[cell]) return;
        ctx.fillStyle = tones[cell];
        ctx.fillRect(x, y, 1, 1);
      });
    });
  }
}

/** "windows", "macos", "android", "ios", "linux" or null. */
function detectOs() {
  const ua = navigator.userAgent;
  const platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
  if (/android/i.test(ua)) return "android";
  if (/iphone|ipad|ipod/i.test(ua)) return "ios";
  // iPadOS reports itself as a Mac but has a touch screen.
  if (/mac/i.test(platform) || /macintosh/i.test(ua)) return navigator.maxTouchPoints > 1 ? "ios" : "macos";
  if (/win/i.test(platform) || /windows/i.test(ua)) return "windows";
  if (/linux|cros/i.test(platform) || /linux|cros/i.test(ua)) return "linux";
  return null;
}

function formatSize(bytes) {
  return `${(bytes / 1024 / 1024).toFixed(1).replace(".", ",")} MB`;
}

async function loadRelease() {
  try {
    // /releases/latest skips pre-releases, so the newest entry of the list is used instead.
    const response = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=10`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(response.status);
    const release = (await response.json()).find((r) => !r.draft && r.assets.length > 0);
    if (!release) throw new Error("kein Release");
    const assets = {};
    for (const [os, pattern] of Object.entries(PATTERNS)) {
      const asset = release.assets.find((a) => pattern.test(a.name));
      if (asset) assets[os] = { url: asset.browser_download_url, size: asset.size, name: asset.name };
    }
    return { tag: release.tag_name, prerelease: release.prerelease, date: release.published_at, url: release.html_url, assets };
  } catch {
    const assets = {};
    for (const [os, name] of Object.entries(FALLBACK.files)) {
      assets[os] = { url: `${RELEASES}/download/${FALLBACK.tag}/${name}`, name };
    }
    return { tag: FALLBACK.tag, prerelease: FALLBACK.prerelease, url: `${RELEASES}/tag/${FALLBACK.tag}`, assets };
  }
}

function render(release, os) {
  for (const link of document.querySelectorAll("a[data-asset]")) {
    const asset = release.assets[link.dataset.asset];
    const size = link.parentElement.querySelector(".size");
    if (asset) {
      link.href = asset.url;
      if (size && asset.size) size.textContent = `${asset.name} · ${formatSize(asset.size)}`;
    } else {
      link.href = release.url;
      link.classList.add("disabled");
      if (size) size.textContent = "In dieser Version nicht enthalten";
    }
  }

  const detected = document.getElementById("detected");
  const primary = document.getElementById("primary");
  const label = document.getElementById("primary-label");
  const hint = document.getElementById("primary-hint");
  const asset = release.assets[os];

  if (asset) {
    detected.textContent = `Erkannt: ${NAMES[os]}`;
    primary.href = asset.url;
    label.textContent = `Für ${NAMES[os]} herunterladen`;
    if (asset.size) hint.textContent = `${asset.name} · ${formatSize(asset.size)}`;
    if (os === "macos") hint.textContent += " · nur für Macs mit Apple Silicon (M1 und neuer)";
    const card = document.querySelector(`.platform[data-os="${os}"]`);
    card.classList.add("current");
    card.parentElement.prepend(card);
    for (const details of document.querySelectorAll("details[data-os]")) details.open = details.dataset.os === os;
  } else {
    detected.textContent =
      os === "ios" ? "Für iPhone und iPad gibt es Mobile Slice noch nicht. Wähle unten ein anderes System."
        : os === "linux" ? "Für Linux gibt es Mobile Slice noch nicht. Wähle unten ein anderes System."
        : "Wähle unten dein System.";
    primary.href = "#platforms";
    label.textContent = "Alle Downloads ansehen";
  }

  const date = release.date ? ` · ${new Date(release.date).toLocaleDateString("de-DE")}` : "";
  const version = document.getElementById("version");
  version.textContent = `Version ${release.tag.replace(/^v/, "")}${release.prerelease ? " (Vorabversion)" : ""}${date} · `;
  const all = document.createElement("a");
  all.href = release.url;
  all.textContent = "Versionshinweise";
  version.append(all);
}

drawIcons();
loadRelease().then((release) => render(release, detectOs()));
