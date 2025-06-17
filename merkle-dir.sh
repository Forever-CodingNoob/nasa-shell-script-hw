#!/usr/bin/env bash
export LC_COLLATE=C

# I. argument checking
show_help() {
    cat << EOF
merkle-dir.sh - A tool for working with Merkle trees of directories.

Usage:
  merkle-dir.sh <subcommand> [options] [<argument>]
  merkle-dir.sh build <directory> --output <merkle-tree-file>
  merkle-dir.sh gen-proof <path-to-leaf-file> --tree <merkle-tree-file> --output <proof-file>
  merkle-dir.sh verify-proof <path-to-leaf-file> --proof <proof-file> --root <root-hash>

Subcommands:
  build          Construct a Merkle tree from a directory (requires --output).
  gen-proof      Generate a proof for a specific file in the Merkle tree (requires --tree and --output).
  verify-proof   Verify a proof against a Merkle root (requires --proof and --root).

Options:
  -h, --help     Show this help message and exit.
  --output FILE  Specify an output file (required for build and gen-proof).
  --tree FILE    Specify the Merkle tree file (required for gen-proof).
  --proof FILE   Specify the proof file (required for verify-proof).
  --root HASH    Specify the expected Merkle root hash (required for verify-proof).

Examples:
  merkle-dir.sh build dir1 --output dir1.mktree
  merkle-dir.sh gen-proof file1.txt --tree dir1.mktree --output file1.proof
  merkle-dir.sh verify-proof dir1/file1.txt --proof file1.proof --root abc123def456
EOF
}

die() {
    show_help
    exit 1
}

is_regular_file() {
    test -f "$1" && ! test -L "$1"
}

is_directory() {
    test -d "$1" && ! test -L "$1"
}

is_valid_hash() {
    [[ "$1" =~ ^[0-9A-F]+$|^[0-9a-f]+$ ]]
}

# II. build
mth(){
    local files=("$@")
    local n="${#files[@]}"
    local k=1 i=0

    if test "$n" -eq 0; then
        # this would never happen
        exit 1
    elif test "$n" -eq 1; then
        #echo "hashing file ${files[*]}" >&2
        local file_hash_hex="$(sha256sum "${files[0]}" | awk '{print $1}')"
        tree[0]="${tree[0]}:$file_hash_hex"
        echo -n "$file_hash_hex ${tree[@]}"
        return 0
    fi

    while test $k -lt $n; do ((k *= 2, i += 1)); done
    ((k /= 2))

    local left_ret=($(mth "${files[@]::k}"))
    local left_hash_hex="${left_ret[0]}"
    tree=("${left_ret[@]:1}")

    local right_ret=($(mth "${files[@]:k}"))
    local right_hash_hex="${right_ret[0]}"
    tree=("${right_ret[@]:1}")

    local combined_hex="$left_hash_hex$right_hash_hex"
    local combined_hash_hex="$(echo -n "$combined_hex" | xxd -r -p | sha256sum | awk '{print $1}')"
    tree[$i]="${tree[$i]}:$combined_hash_hex"
    echo -n "$combined_hash_hex ${tree[@]}"
}

build_tree(){
    local dir="$1" output_file="$2"
    local files_rel=($(find "$dir" -type f -printf '%P\n' | sort))
    local files_abs=("${files_rel[@]/#/$dir\/}")

    if test ${#files_rel[@]} -eq 0; then
        # this would never happen
        echo "no files provided" >&2
        exit 1
    fi

    declare -a tree=()
    local ret=($(mth "${files_abs[@]}"))
    tree=("${ret[@]:1}")

    IFS=$'\n'
    echo -e "${files_rel[*]}\n\n${tree[*]/#:/}" > "$output_file"

    return 0
}

# III. gen-proof
get_node(){
    local i=$1 j=$2 k=1 l=0
    local n=$((j-i+1))
    while test $k -lt $n; do ((k *= 2, l += 1)); done
    IFS=':'
    local hash_list=(${tree[$l]/#:/})
    echo -n "${hash_list[i/k]}"
}

inclusion_proof(){
    local idx=$1 l=$2 r=$3
    local n=$((r-l+1))
    test $n -eq 1 && echo -n "" && return 0

    local k=1
    while test $k -lt $n; do ((k *= 2)); done
    ((k /= 2, k += l))

    if test $idx -lt $k; then
        echo -en "$(inclusion_proof $idx $l $((k-1)))\n$(get_node $k $r)"
    else
        echo -en "$(inclusion_proof $idx $k $r)\n$(get_node $l $((k-1)))"
    fi
}

gen_proof(){
    local leaf_file="$1" tree_file="$2" output_file="$3"
    mapfile -t lines < "$tree_file"

    local n=0
    while test -n "${lines[$n]}"; do ((n++)); done
    local file_paths=("${lines[@]::n}")
    tree=("${lines[@]:n+1}")

    local leaf_index=-1
    for i in "${!file_paths[@]}"; do
        test "${file_paths[$i]}" = "$leaf_file" && leaf_index=$i && break
    done
    test $leaf_index -eq -1 && echo "ERROR: file not found in tree" && exit 1

    # compute inclusion proof
    local proof="$(inclusion_proof $leaf_index 0 $((n-1)))"
    echo -e "leaf_index:$((leaf_index+1)),tree_size:$n\n${proof/#$'\n'/}" > "$output_file"
    return 0
}

# IV. verify-proof
invalidate_proof(){
    echo "Verification Failed"
    exit 1
}

validate_proof(){
    echo "OK"
    exit 0
}

verify(){
    local leaf_file="$1" proof_file="$2" root_hash="$3"
    mapfile -t lines < "$proof_file"
    if ! [[ "${lines[0]}" =~ leaf_index:([0-9]+),tree_size:([0-9]+) ]]; then
        # this should never happen
        echo "invalid proof file" >&2
        exit 1
    fi

    local k n h pi h_ast
    ((k=${BASH_REMATCH[1]}-1, n=${BASH_REMATCH[2]}-1))
    h="$(sha256sum "$leaf_file" | awk '{print $1}')"
    pi=("${lines[@]:1}")

    for h_i in "${pi[@]}"; do
        test $n -eq 0 && invalidate_proof
        if test $((k%2)) -eq 1 || test $k -eq $n; then
            h="$(echo -n "$h_i$h" | xxd -r -p | sha256sum | awk '{print $1}')"
            while test $((k%2)) -eq 0; do
                ((k>>=1, n>>=1))
            done
        else
            h="$(echo -n "$h$h_i" | xxd -r -p | sha256sum | awk '{print $1}')"
        fi
        ((k>>=1, n>>=1))
    done
    test $n -eq 0 && test "${h,,}" = "${root_hash,,}" && validate_proof || invalidate_proof
}

# main function
main(){
    if test $# -eq 0; then
        show_help
        exit 1
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
        -h|--help)
            if test $# -eq 0; then
                show_help
                exit 0
            else
                die
            fi
            ;;
        build)
            local directory=""
            local output=""
            while test $# -gt 0; do
                case "$1" in
                    --output)
                        output="$2"
                        shift; shift
                        ;;
                    *)
                        if test -z "$directory"; then
                            directory="$1"
                        else
                            die
                        fi
                        shift
                        ;;
                esac
            done
            if test -z "$directory" || test -z "$output" || ! is_directory "$directory" || { test -e "$output" && ! is_regular_file "$output"; }; then
                die
            fi
            build_tree "$directory" "$output"
            ;;

        gen-proof)
            local leaf_file=""
            local tree_file=""
            local output=""
            while test $# -gt 0; do
                case "$1" in
                    --tree)
                        tree_file="$2"
                        shift; shift
                        ;;
                    --output)
                        output="$2"
                        shift; shift
                        ;;
                    *)
                        if test -z "$leaf_file"; then
                            leaf_file="$1"
                        else
                            die
                        fi
                        shift
                        ;;
                esac
            done
            if test -z "$leaf_file" || test -z "$tree_file" || test -z "$output" || ! is_regular_file "$tree_file" || { test -e "$output" && ! is_regular_file "$output"; }; then
                die
            fi
            gen_proof "$leaf_file" "$tree_file" "$output"
            ;;

        verify-proof)
            local leaf_file=""
            local proof_file=""
            local root_hash=""
            while test $# -gt 0; do
                case "$1" in
                    --proof)
                        proof_file="$2"
                        shift; shift
                        ;;
                    --root)
                        root_hash="$2"
                        shift; shift
                        ;;
                    *)
                        if test -z "$leaf_file"; then
                            leaf_file="$1"
                        else
                            die
                        fi
                        shift
                        ;;
                esac
            done
            if test -z "$leaf_file" || test -z "$proof_file" || test -z "$root_hash" || ! is_regular_file "$leaf_file" || ! is_regular_file "$proof_file" || ! is_valid_hash "$root_hash"; then
                die
            fi
            verify "$leaf_file" "$proof_file" "${root_hash,,}"
            ;;

        *)
            die
            ;;
    esac
}

main "$@"
