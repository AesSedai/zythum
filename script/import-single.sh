#!/bin/bash
#
# Import script for zythum
# Load a single mod into the game and analyze it
#

FACTORIO_MODS="https://mods.factorio.com/mods/"
FACTORIO_PATH=/Applications/factorio.app/Contents/MacOS/factorio
FACTMODS_PATH=~/Library/Application\ Support/factorio/mods
FACTMODS_GRAB=./script/grabber
TEMPLOGS_PATH=./temp.log
TEMPFILE_DIRS=./temp
FACTORIO_TIME=15

IMPORT_FILE=$1
IMPORT_INEW=$2
IMPORT_BASE=$3
IMPORT_NEWF=./

urlencode() {
  old_lc_collate=$LC_COLLATE
  LC_COLLATE=C
  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
    local c="${1:i:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
      *) printf '%%%02X' "'$c" ;;
    esac
  done
  LC_COLLATE=$old_lc_collate
}

rm -rf "$TEMPFILE_DIRS"
mkdir -p "$TEMPFILE_DIRS"

# Check if the user wants to import a valid file
if [[ ! -e "$IMPORT_FILE" ]]; then
  echo "ER: Import mod file does not exist"
  exit 1
fi

# Check if the user wants to overwrite the mods
if [[ "$2" == "new" ]]; then
  IMPORT_NEWF=./mods/
else
  IMPORT_NEWF=./import/
  mkdir -p ./import
fi

# Copy the file to analize and the mod analyzer to the mod directory
if [[ -d "$FACTMODS_PATH" ]]; then
  echo "OK: Loading mod file and mod analyzer"
  cp ./mods/base.lua "$FACTMODS_GRAB/baseset.lua"
  cp ./config.lua "$FACTMODS_GRAB/config.lua"

  ls "$FACTMODS_PATH" | while read FILE; do
    rm -rf "$FACTMODS_PATH/$FILE"
  done

  # Copy dependency package, if the user added any
  if [[ "$IMPORT_BASE" != "" ]]; then
    cp "$IMPORT_BASE" "$FACTMODS_PATH"
  fi

  cp -r "$FACTMODS_GRAB" "$FACTMODS_PATH"
  mv "$FACTMODS_PATH/grabber" "$FACTMODS_PATH/zythumgrabber_1.0.0"

  cp "$IMPORT_FILE" "$FACTMODS_PATH"

  rm "$FACTMODS_GRAB/baseset.lua"
  rm "$FACTMODS_GRAB/config.lua"
else
  echo "ER: Factorio mod directory does not exist"
fi

# Copy or extract the file to the import to get info.json
MODPATH="$TEMPFILE_DIRS"
unzip "$IMPORT_FILE" -d "$TEMPFILE_DIRS" > /dev/null 2>&1
while read FILE; do
  MODPATH="$TEMPFILE_DIRS/$FILE"
done < <(ls "$TEMPFILE_DIRS")

if [[ -e "$MODPATH/info.json" ]]; then
  echo "OK: Analyzing info.json"
  LINE_NAME=$(cat "$MODPATH/info.json" | grep name)
  LINE_TITLE=$(cat "$MODPATH/info.json" | grep title)
  LINK_OWNER=$(cat "$MODPATH/info.json" | grep author)
  MOD_NAME=$(echo $LINE_NAME| cut -d'"' -f 4)
  MOD_TITLE=$(echo $LINE_TITLE| cut -d'"' -f 4)
  MOD_OWNER=$(echo $LINK_OWNER| cut -d'"' -f 4)

  if [[ "$MOD_NAME" == "" ]]; then MODNAME="unknown"; fi
  if [[ "$MOD_TITLE" == "" ]]; then MODNAME="unknown"; fi
  if [[ "$MOD_OWNER" == "" ]]; then MODNAME="unknown"; fi


  MOD_OWNER_E=$(urlencode $MOD_OWNER)
  MOD_NAME_E=$(urlencode $MOD_NAME)
  MOD_LINK="$FACTORIO_MODS$MOD_OWNER_E/$MOD_NAME_E"
else
  echo "ER: Mod file does not contain an info.json"
fi

# Run factorio in order to grab all the mod information
echo "OK: Loading factorio with mod file and mod analyzer"
gtimeout $FACTORIO_TIME "$FACTORIO_PATH" > "$TEMPLOGS_PATH"
MODGRAB_DATA=$(cat "$TEMPLOGS_PATH" | grep "zythumgrab>")
MODGRAB_VERS=$(cat "$TEMPLOGS_PATH" | grep "Loading mod")
rm $TEMPLOGS_PATH

# Get the actual information from the factorio log
FINAL_VERSION="0.0.0"
FINAL_NAME=""

LOADINDEX=0
while read -r LINE; do
  if [[ $LOADINDEX -eq 2 ]]; then
    if [[ $LINE =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
      FINAL_VERSION="${BASH_REMATCH[0]}"
    fi
    if [[ $LINE =~ Loading\ mod\ (.*)\ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
      FINAL_NAME="${BASH_REMATCH[1]}"
    fi
  fi
  LOADINDEX=$(($LOADINDEX + 1))
done <<< "$MODGRAB_VERS"

FILE_NAME="$IMPORT_NEWF$FINAL_NAME.lua"

echo "-- zythum sorter" > "$FILE_NAME"
echo "-- tidy up your factorio ui" >> "$FILE_NAME"
echo "--" >> "$FILE_NAME"
echo "-- file: mods/$FINAL_NAME.lua" >> "$FILE_NAME"
echo "-- name: $MOD_TITLE" >> "$FILE_NAME"
echo "-- link: $MOD_LINK" >> "$FILE_NAME"
echo "-- author: cybrox" >> "$FILE_NAME"
echo "-- refver: $FINAL_VERSION" >> "$FILE_NAME"
echo "" >> "$FILE_NAME"
echo "zythum_sort_mod('$FINAL_NAME')" >> "$FILE_NAME"
tail -n39 ./mods/_template.lua >> "$FILE_NAME"

# Append all the scanned items to the template
while read -r LINE; do
  ITEM=$(echo $LINE| cut -d'>' -f 2)
  echo "zythum_sort('CATEGORY', 00, 00, '$ITEM')" >> "$FILE_NAME"
done <<< "$MODGRAB_DATA"

# Remove temp unpack dirctory
rm -rf "$TEMPFILE_DIRS"

# Regenerate README and modpack
bash ./script/generate-imports.sh
bash ./script/generate-readme.sh
