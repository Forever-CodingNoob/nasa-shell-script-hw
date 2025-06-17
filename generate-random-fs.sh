#!/usr/bin/env bash

# Usage: ./generate_random_fs.sh <target_directory> <max_depth> <max_total_entries> <max_entries_per_dir>
# Example: ./generate_random_fs.sh ./testdir 3 50 5

TARGET_DIR="${1:-./random_fs}"  # Default to ./random_fs if no argument is given
MAX_DEPTH="${2:-3}"  # Max depth of nested directories
MAX_TOTAL_ENTRIES="${3:-50}"  # Max total number of entries in the entire structure
MAX_ENTRIES="${4:-10}"  # Max number of entries per directory

CURRENT_ENTRIES=0  # Keep track of how many entries we've created

# 春日影 Lyrics (Each line is an element in the array)
LYRICS=(
    "悴んだ心 ふるえる眼差し世界で"
    "僕は ひとりぼっちだった"
    "散ることしか知らない春は"
    "毎年 冷たくあしらう"
    "暗がりの中 一方通行に ただただ"
    "言葉を書き殴って 期待するだけ"
    "むなしいと分かっていても"
    "救いを求め続けた"
    "（せつなくて いとおしい）"
    "今ならば 分かる気がする"
    "（しあわせで くるおしい）"
    "あの日泣けなかった僕を"
    "光は やさしく連れ立つよ"
    "雲間をぬって きらりきらり"
    "心満たしては 溢れ"
    "いつしか頬を きらりきらり"
    "熱く 熱く濡らしてゆく"
    "君の手は どうしてこんなにも温かいの？"
    "ねぇお願い どうかこのまま 離さないでいて"
    "縁を結んでは ほどきほどかれ"
    "誰しもがそれを喜び悲しみながら"
    "愛を数えてゆく"
    "鼓動を確かめるように"
    "（うれしくて さびしくて）"
    "今だから 分かる気がした"
    "（たいせつで こわくって）"
    "あの日泣けなかった僕を"
    "光は やさしく抱きしめた"
    "照らされた世界 咲き誇る大切な人"
    "あたたかさを知った春は 僕のため 君のための"
    "涙を流すよ"
    "Ah なんて眩しいんだろう"
    "Ah なんて美しいんだろう"
    "雲間をぬって きらりきらり"
    "心満たしては 溢れ"
    "いつしか頬を きらりきらり"
    "熱く 熱く濡らしてゆく"
    "君の手は どうしてこんなにも温かいの？"
    "ねぇお願い どうかこのまま 離さないでいて"
    "ずっと ずっと 離さないでいて"
)

# Generate a random name with allowed characters (a-zA-Z0-9 _ - .)
# Ensures the name does NOT start with a hyphen (-)
generate_name() {
    local length=$(( RANDOM % 8 + 5 ))  # Random length between 5 and 12
    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
    local first_chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."  # Excludes '-'
    local name=""
    local i

    name="${first_chars:RANDOM % ${#first_chars}:1}"  # Ensure first character is valid
    for (( i=1; i<length; i++ )); do
        name+="${chars:RANDOM % ${#chars}:1}"
    done

    echo "$name"
}

# Generate random lyrics content for a file
generate_file_content() {
    local file_path="$1"
    local num_lines=$(( RANDOM % 10 + 5 ))  # Random number of lines (5 to 15)
    local i

    for (( i=0; i<num_lines; i++ )); do
        echo "${LYRICS[RANDOM % ${#LYRICS[@]}]}" >> "$file_path"
    done
}

generate_random_fs() {
    local current_dir="$1"
    local current_depth="$2"
    local i
    local existing_entries=()  # Track used names in this directory

    if (( current_depth > MAX_DEPTH || CURRENT_ENTRIES >= MAX_TOTAL_ENTRIES )); then
        return
    fi

    # Decide how many entries to create in this directory (ensuring we don't exceed the limit)
    local num_entries=$(( RANDOM % MAX_ENTRIES + 1 ))

    for (( i = 0; i < num_entries; i++ )); do
        if (( CURRENT_ENTRIES >= MAX_TOTAL_ENTRIES )); then
            return
        fi

        local name
        while :; do
            name=$(generate_name)  # Generate a random name
            if [[ ! " ${existing_entries[@]} " =~ " ${name} " ]]; then
                break  # Ensure the name is unique in this directory
            fi
        done
        existing_entries+=("$name")  # Store the used name

        local choice=$(( RANDOM % 3 ))

        case $choice in
            0)  # Create a regular file with random lyrics
                local file_path="$current_dir/$name"
                touch "$file_path"
                generate_file_content "$file_path"
                echo "Created file: $file_path (filled with lyrics)"
                (( CURRENT_ENTRIES++ ))  # Increment total entry count
                ;;
            1)  # Create a directory
                mkdir "$current_dir/$name"
                echo "Created directory: $current_dir/$name"
                (( CURRENT_ENTRIES++ ))  # Increment total entry count
                generate_random_fs "$current_dir/$name" $(( current_depth + 1 ))
                ;;
            2)  # Create a symlink (only if there's something to link to)
                if [ ${#existing_entries[@]} -gt 0 ]; then
                    local target="${existing_entries[RANDOM % ${#existing_entries[@]}]}"
                    ln -s "$current_dir/$target" "$current_dir/$name"
                    echo "Created symlink: $current_dir/$name -> $target"
                    (( CURRENT_ENTRIES++ ))  # Increment total entry count
                fi
                ;;
        esac
    done
    test $i -eq $num_entries || exit 1
}

# Ensure the target directory exists and start generation
mkdir -p "$TARGET_DIR"
generate_random_fs "$TARGET_DIR" 1
echo "total number of files/dirs/symlinks: $CURRENT_ENTRIES"
