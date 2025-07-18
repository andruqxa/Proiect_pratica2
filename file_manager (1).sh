#!/bin/bash

# === Configurari generale ===
OMDB_API_KEY="a6572829"
DOWNLOADS_DIR="Downloads"
MEDIA_DIR="Media"
DOCUMENTS_DIR="Documents"
EXECUTABLES_DIR="Executables"
LOG_FILE="mutari.log"
API_QUERY_COUNT_FILE="api_query_count.txt"
MAX_API_QUERIES=1000

# === Functie: Logare mutari in fisier ===
log_move() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Mutat: $1 -> $2" >> "$LOG_FILE"
}

# === Functie: Evitarea suprascrierii fisierelor existente ===
generate_unique_filename() {
    local filepath="$1"
    local dest_dir="$2"
    local filename=$(basename "$filepath")
    local dest_path="$dest_dir/$filename"

    local counter=1
    while [ -e "$dest_path" ]; do
        dest_path="${dest_dir}/${filename%.}_$counter.${filename##.}"
        counter=$((counter + 1))
    done
    echo "$dest_path"
}

# === Functii: Management cereri OMDb ===
get_api_query_count() {
    if [ ! -f "$API_QUERY_COUNT_FILE" ]; then
        echo 0 > "$API_QUERY_COUNT_FILE"
    fi
    cat "$API_QUERY_COUNT_FILE"
}

increment_api_query_count() {
    local count=$(get_api_query_count)
    count=$((count + 1))
    echo "$count" > "$API_QUERY_COUNT_FILE"
}

check_api_limit() {
    local count=$(get_api_query_count)
    if [ "$count" -ge "$MAX_API_QUERIES" ]; then
        echo "Limita de 1000 cereri OMDb pe zi a fost atinsa."
        exit 1
    fi
}

reset_api_count_daily() {
    local current_day=$(date +%Y-%m-%d)
    local last_run_day=$(cat last_run_day.txt 2>/dev/null || echo "")

    if [ "$current_day" != "$last_run_day" ]; then
        echo "Resetam contorul API pentru o noua zi."
        echo 0 > "$API_QUERY_COUNT_FILE"
        echo "$current_day" > last_run_day.txt
    fi
}

#Functii - procesare fisiere

# Filme - folosim OMDb API
handle_movie() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    local title="${filename%.*}"

    check_api_limit
    response=$(curl -s "http://www.omdbapi.com/?t=${title// /%20}&apikey=$OMDB_API_KEY")
    increment_api_query_count

    year=$(echo "$response" | jq -r '.Year')
    if [ "$year" = "null" ] || [ -z "$year" ]; then
        year="Unknown"
    fi
    
    dest="$MEDIA_DIR/Movies/$year/$title"
    mkdir -p "$dest"
    unique_dest=$(generate_unique_filename "$filepath" "$dest")
    mv "$filepath" "$unique_dest"
    log_move "$filepath" "$unique_dest"
    echo "$response" > "$dest/metadata.json"
    echo "Film mutat: $filepath -> $unique_dest"
}

# Seriale - detectam sezon/episod
handle_series() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    local name="${filename%.*}"

    if [[ "$name" =~ [Ss]([0-9]+)[Ee]([0-9]+) ]]; then
        season=$(printf "%02d" "${BASH_REMATCH[1]}")
        episode=$(printf "%02d" "${BASH_REMATCH[2]}")
        series_name=$(echo "$name" | sed 's/[Ss][0-9][0-9][Ee][0-9][0-9].//' | sed 's/[._-]$//')
        dest="$MEDIA_DIR/Series/$series_name/S$season/E$episode"
        mkdir -p "$dest"
        unique_dest=$(generate_unique_filename "$filepath" "$dest")
        mv "$filepath" "$unique_dest"
        log_move "$filepath" "$unique_dest"
        echo "Serial mutat: $filepath -> $unique_dest"
    else
        echo "Nu s-a putut detecta formatul S##E## pentru: $filename"
    fi
}

# Muzica - presupunem format Artist - Cantec
handle_music() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    local name="${filename%.*}"

    if [[ "$name" =~ ^(.+)[[:space:]]-[[:space:]](.+)$ ]]; then
        artist=$(echo "${BASH_REMATCH[1]}" | xargs)
        song=$(echo "${BASH_REMATCH[2]}" | xargs)
        dest="$MEDIA_DIR/Music/$artist"
        mkdir -p "$dest"
        unique_dest=$(generate_unique_filename "$filepath" "$dest")
        mv "$filepath" "$unique_dest"
        log_move "$filepath" "$unique_dest"
        echo "Muzica mutata: $filepath -> $unique_dest"
    else
        #Daca nu gasim format "Artist - Cantec", punem in folder Unknown
        dest="$MEDIA_DIR/Music/Unknown"
        mkdir -p "$dest"
        unique_dest=$(generate_unique_filename "$filepath" "$dest")
        mv "$filepath" "$unique_dest"
        log_move "$filepath" "$unique_dest"
        echo "Muzica mutata in Unknown: $filepath -> $unique_dest"
    fi
}

# Documente si executabile
handle_misc() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    local extension="${filename##*.}"

    case "$extension" in
        pdf|doc|docx|odt)
            dest="$DOCUMENTS_DIR"
            mkdir -p "$dest"
            unique_dest=$(generate_unique_filename "$filepath" "$dest")
            mv "$filepath" "$unique_dest"
            log_move "$filepath" "$unique_dest"
            echo "Document mutat: $filepath -> $unique_dest"
            ;;
        exe|sh|bat)
            dest="$EXECUTABLES_DIR"
            mkdir -p "$dest"
            unique_dest=$(generate_unique_filename "$filepath" "$dest")
            mv "$filepath" "$unique_dest"
            log_move "$filepath" "$unique_dest"
            echo "Executabil mutat: $filepath -> $unique_dest"
            ;;
        *)
            echo "[ALT TIP] Fisier ignorat: $filepath"
            return 1
            ;;
    esac
}

#Resetam contorul zilnic (daca e cazul)
reset_api_count_daily

#Parcurgem fisierele din Downloads
find "$DOWNLOADS_DIR" -type f | while read -r filepath; do
    filename=$(basename "$filepath")
    extension="${filename##*.}"
    
    #Determinam calea relativa fata de Downloads
    relative_path=${filepath#$DOWNLOADS_DIR/}
    
    #Verificam daca fisierul este in subdirectoare specifice
    if [[ "$relative_path" == Movies/* ]]; then
        handle_movie "$filepath"
    elif [[ "$relative_path" == Series/* ]]; then
        handle_series "$filepath"
    elif [[ "$relative_path" == Music/* ]]; then
        handle_music "$filepath"
    else
        #Fisierul este direct in Downloads sau in alt subdirector
        case "$extension" in
            pdf|odt|doc|docx|exe|sh|bat)
                handle_misc "$filepath"
                ;;
            mp4|mkv|avi|mov|wmv|flv|webm|m4v)
                echo "Film detectat in Downloads: $filepath"
                handle_movie "$filepath"
                ;;
            mp3|flac|wav|aac|ogg|wma|m4a)
                echo "Muzica detectata in Downloads: $filepath"
                handle_music "$filepath"
                ;;
            *)
                echo "[ALT TIP] Fisier ignorat: $filepath"
                ;;
        esac
    fi
done

echo "Script incheiat"
