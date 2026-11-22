#!/usr/bin/env bash
# Regenerates the adaptive launcher icon (pixel art on an 18x18 grid) into android res/.
set -euo pipefail
RES="$(cd "$(dirname "$0")/.." && pwd)/android/app/src/main/res"
GRID=(
'..................'
'..................'
'........KK........'
'......KKYYKK......'
'....KKYYYYYYKK....'
'..KKYYYYYYYYYYKK..'
'..KOOYYYYYYYYDDK..'
'..KOOOOYYYYDDDDK..'
'..KOOOOOYYDDDDDK..'
'..KOOOOOODDDDDDK..'
'..KooooooddddddK..'
'..KOOOOOODDDDDDK..'
'..KooooooddddddK..'
'..KOOOOOODDDDDDK..'
'..KKOOOOODDDDDKK..'
'....KKOOODDDKK....'
'......KKODKK......'
'........KK........'
)
declare -A COLOR=([K]=0D0D18 [W]=F2EFE6 [Y]=FFD447 [O]=FF8A3D [o]=D9692A [D]=C25E22 [d]=99461A)
# Path for all pixels whose char is in $1, horizontal runs merged.
path() {
  local chars="$1" out="" y x n row
  for y in "${!GRID[@]}"; do
    row="${GRID[$y]}"; x=0
    while (( x < ${#row} )); do
      if [[ "$chars" == *"${row:x:1}"* ]]; then
        n=1; while (( x + n < ${#row} )) && [[ "$chars" == *"${row:x+n:1}"* ]]; do n=$((n+1)); done
        out+="M$x,${y}h${n}v1h-${n}z"; x=$((x+n))
      else x=$((x+1)); fi
    done
  done
  printf '%s' "$out"
}
# 3.5dp pixels keep the art inside the 66dp safe zone of the 108dp canvas.
head='<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <group android:translateX="22.5" android:translateY="19" android:scaleX="3.5" android:scaleY="3.5">'
tail='    </group>
</vector>'
mkdir -p "$RES/drawable" "$RES/mipmap-anydpi-v26" "$RES/values"
{
  echo "$head"
  # Android cannot inflate a vector with an empty path, so unused colors are skipped.
  for c in K W Y O o D d; do d="$(path "$c")"; if [[ -n "$d" ]]; then echo "        <path android:fillColor=\"#${COLOR[$c]}\" android:pathData=\"$d\" />"; fi; done
  echo "$tail"
} > "$RES/drawable/ic_launcher_foreground.xml"
# Themed (Android 13+) icon: alpha only, so the outline and layer lines become gaps.
{
  echo "$head"
  echo "        <path android:fillColor=\"#FFFFFFFF\" android:pathData=\"$(path WYOD)\" />"
  echo "$tail"
} > "$RES/drawable/ic_launcher_monochrome.xml"
cat > "$RES/values/ic_launcher_colors.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1B1B2F</color>
</resources>
XML
cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
XML
