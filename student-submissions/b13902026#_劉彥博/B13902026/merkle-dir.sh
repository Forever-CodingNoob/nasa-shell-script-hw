#!/usr/bin/env bash

#variables
subcommand=0
options=0
ARG=""
help=""
build=""
gen_proof=""                                            
verify_proof=""
output=""
tree=""
proof=""                     
hash_num=""

declare -A arr #for memorizing the R[a..b]


#functions
print_usage(){
  echo "merkle-dir.sh - A tool for working with Merkle trees of directories.

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
  merkle-dir.sh verify-proof dir1/file1.txt --proof file1.proof --root abc123def456">&1
}

checkbuild(){
  if [[ -z "$output" ]]; then
    echo "false"
  fi
  if [[ "$options" == "1" ]] && ([[ ! -e "$output" ]] || ([[ -f "$output" ]] && [[ ! -L "$output" ]])) && [[ -d "$ARG" ]] && [[ ! -L "$ARG" ]]; then
    echo "true"
  else
    echo "false"
  fi  
}

checkgenproof(){
  if [[ -z "$output" ]] || [[ -z "$tree" ]]; then
    echo "false"
  fi
  if [[ "$options" == "2" ]] && ([[ ! -e "$output" ]] || ([[ -f "$output" ]] && [[ ! -L "$output" ]])) && [[ -n "$ARG" ]] && [[ -f "$tree" ]] && [[ ! -L "$tree" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

checkverifyproof(){
  if [[ -z "$proof" ]] || [[ -z "$hash_num" ]] || [[ -z "$ARG" ]]; then
    echo "false"
  fi
  if [[ "$options" == "2" ]] && [[ -f "$proof" ]] && [[ ! -L "$proof" ]] && ([[ "$hash_num" =~ ^[0-9A-F]+$ ]] || [[ "$hash_num" =~ ^[0-9a-f]+$ ]]) &&[[ -f "$ARG" ]] && [[ ! -L "$ARG" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

#--------------------------------------help build tree (separate hex and h bad:(  )
multi_hex(){
  echo -n "$1$2" | xxd -r -p | sha256sum | awk '{print $1}'
}

traverse_file(){ #recursively traverse the file， find their path then delete the front
  local dir="$1"
  for file in "$dir"/* "$dir"/.*; do
    if [[ -f "$file" ]] && [[ ! -L "$file" ]]; then
      echo "${file#"$2"/}" >> "$output"
    elif [[ -d "$file" ]] && [[ ! -L "$file" ]]; then
      traverse_file "$file" "$2"
    fi
  done
}
#-------------------------------------build_tree

build_tree(){
  echo -n "" > "$output" #just reset
  (traverse_file $ARG $ARG)  
  n=1
  LC_COLLATE=C sort -o "$output" "$output" #put the sorted result in the outputfile
    while IFS= read -r line; do #get all files in dictionary order :)
    abs_path="$ARG"/"$line"
    arr[$n,$n]=$( sha256sum "$abs_path" | awk '{print $1}') #| xxd -r -p ) #| tr '\000' '\n' )
    ((n++))
  done < "$output"
  echo "" >> "$output"
  ((n--))
  level=0
  two_k=1
  two_smallk=0
  while [[ "$two_smallk" -lt "$n" ]]; do
  first=""
  floor=$((n/two_k))
  start_index="1"
  end_index="$two_k"
  if [[ $level == "0" ]] || (((n % two_k) <= two_smallk)); then #case 1
  for((i=0; i < floor; i++));do
  if [[ -z ${arr[$start_index,$end_index]} ]]; then
    arr[$start_index,$end_index]=$( multi_hex "${arr[$start_index,$((start_index+two_smallk-1))]}" "${arr[$((start_index+two_smallk)),$end_index]}" )
  fi  
  if [[ -n "$first" ]]; then
  echo -n ":">>"$output"
  fi
  first=123
  echo -n "${arr[$start_index,$end_index]}">>"$output"
  ((start_index+=two_k))
  ((end_index+=two_k))
  done #for end
  echo "">>"$output"
#-----
  else #case 2
  for((i=0; i < floor; i++));do
  if [[ -z ${arr[$start_index,$end_index]} ]]; then
    arr[$start_index,$end_index]=$( multi_hex "${arr[$start_index,$((start_index+two_smallk-1))]}" "${arr[$((start_index+two_smallk)),$end_index]}" )
  fi  
  if [[ -n "$first" ]]; then
  echo -n ":">>"$output"
  fi
  first=123
  echo -n "${arr[$start_index,$end_index]}">>"$output"
  ((start_index+=two_k))
  ((end_index+=two_k))
  done #for end
  if [[ -n "$first" ]]; then
  echo -n ":">>"$output"
  fi
  end_index="$n"
  if [[ -z ${arr[$start_index,$end_index]} ]]; then
    arr[$start_index,$end_index]=$( multi_hex "${arr[$start_index,$((start_index+two_smallk-1))]}" "${arr[$((start_index+two_smallk)),$end_index]}" )
  fi 
  echo -n "${arr[$start_index,$end_index]}">>"$output"
  echo "">>"$output"
  fi
  if [[ "$level" != "0" ]]; then
  two_k=$((two_k*2))
  two_smallk=$((two_smallk*2))
  else
  two_k=2
  two_smallk=1
  fi
  ((level++))
  done
}

#-----------------------------------help gen_inclusion
get_smallk(){ #get 2^[m-1]
  m="$1"
  k=1
  while [[ $((k*2)) -le "$m" ]]; do
    ((k*=2))
  done
  echo "$k"
}

get_r(){
  if [[ -n ${arr["$1","$2"]} ]]; then
    echo -n "${arr["$1","$2"]}"
  else
    local starting="$1"
    local ending="$2"
    m=$((ending-starting)) #actually m-1
    k=$( get_smallk "$m" )
    arr["$starting","$ending"]=$( multi_hex "$( get_r "$starting" "$((starting+k-1))")" "$( get_r "$((starting+k))" "$ending")" )
    echo -n "${arr["$starting","$ending"]}"
  fi
}
#-------------------------------------
#-------------------------------------gen_inclusion
gen_inclusion(){
  > "$output" #just reset
  output_hashes=() #output from last to first
  found="" #if found the file, then found is the index of the given file
  n=1
  while IFS= read -r line; do 
    if [[ -z "$line" ]]; then
      break
    elif [[ "$line" == "$ARG" ]]; then
      found="$n"
    fi
    ((n++))
  done < "$tree"
  #now n is the total_number_of_files+1 and the line_number of the blank line
  if [[ -z "$found" ]]; then
    echo "ERROR: file not found in tree">&1
    exit 1
  fi
  line=$(sed -n "$((n+1))p" "$tree")
  IFS=":" read -ra hashes <<< "$line"
  i=1
  while [[ "$i" -le ${#hashes[@]} ]]; do
    arr["$i","$i"]=${hashes[$((i-1))]}
    ((i++))
  done
  ((n--))
  echo "leaf_index:"$found",tree_size:"$n"">>"$output"
  front="$found"
  starting=1
  ending="$n"
  cur=0 #current index of the output_hashes array
  while [[ "$((ending-starting))" -gt 0 ]]; do
  m=$((ending-starting)) #actually m-1
  k=$(get_smallk "$m")
  if [[ "$front" -le "$k" ]]; then #case 1
    output_hashes["$cur"]="$(get_r $((starting+k)) "$ending" )"
    ending=$((starting+k-1))
  else #case 2
    output_hashes["$cur"]="$(get_r "$starting" $((starting+k-1)))"
    ((front-=k))
    ((starting+=k))
  fi
  ((cur++))
  done

  i="${#output_hashes[@]}"
  ((i--))
  while [[ "$i" -ge 0 ]]; do
    echo "${output_hashes["$i"]}">>"$output"
    ((i--))
  done
}
#-------------------------------------
#-------------------------------------verify_correctness
verify_correctness(){
  inclusion_proofs=()
  f="$ARG"
  cur=0
  first_line=true
  while IFS= read -r line; do
    if [[ "$first_line" == "true" ]]; then
    k=$( echo -n "$line" | awk -F '[:,]' '{print $2}' )
    n=$( echo -n "$line" | awk -F '[:,]' '{print $4}' )
    first_line=false
    else
    inclusion_proofs["$cur"]="$line"
    ((cur++))
    fi
  done < "$proof"
  k=$((k-1)) #k'
  n=$((n-1)) #n'
  h=$( sha256sum "$f" | awk '{print $1}')
  for ((i=0;i<cur;i++))do
    if [[ "$n" == "0" ]]; then
    echo "Verification Failed">&1
    exit 1
    fi
    if ((((k & 1) == 1) || (k == n) )); then 
      h=$( multi_hex "${inclusion_proofs[$i]}" "$h" )
      while (((k & 1) == 0)); do
        ((k>>=1))
        ((n>>=1))
      done
    else
      h=$( multi_hex "$h" "${inclusion_proofs[$i]}" )
    fi
    ((k>>=1))
    ((n>>=1))
  done
  if ((n == 0)) && [[ "${h,,}" == "${hash_num,,}" ]]; then #turn them all to lower case letters
    echo "OK">&1
    exit 0
  else
    echo "Verification Failed">&1
    exit 1 
  fi
}
#-------------------------------------
#parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    build)
      build=true
      ((subcommand+=1))
      shift
      ;;
    gen-proof)
      gen_proof=true
      ((subcommand+=1))
      shift
      ;;
    verify-proof)
      verify_proof=true
      ((subcommand+=1))
      shift
      ;;
    -h)
      help=true
      ((options+=1))
      shift
      ;;
    --help)
      help=true
      ((options+=1))
      shift
      ;;
    --output)
      if [[ -n "$2" ]] && [[ "$2" != --* ]]; then
        output=$2
        ((options+=1))
        shift 2
      else
        print_usage
        exit 1
      fi
      ;;
    --tree)
      if [[ -n "$2" ]] && [[ "$2" != --* ]]; then
        tree=$2
        ((options+=1))
        shift 2
      else
        print_usage
        exit 1
      fi
      ;;
    --proof)
      if [[ -n "$2" ]] && [[ "$2" != --* ]]; then
        proof=$2
        ((options+=1))
        shift 2
      else
        print_usage
        exit 1
      fi
      ;;
    --root)
      if [[ -n "$2" ]] && [[ "$2" != --* ]]; then
        hash_num=$2
        ((options+=1))
        shift 2
      else
        print_usage
        exit 1
      fi
      ;;
    *)
        if [[ -n "$ARG" ]]; then
          print_usage
          exit 1
        else
        ARG=$1
        shift
        fi
        ;;
  esac
done

if [[ "$subcommand" -gt 1 ]]; then
  print_usage
  exit 1
elif [[ "$options" == "1" ]] && [[ "$help" == "true" ]] && [[ -z "$ARG" ]] && [[ "$subcommand" == "0" ]]; then
  print_usage
  exit 0
elif [[ "$build" == "true" ]] && [[ "$(checkbuild)" == "true" ]]; then
  build_tree
  exit 0  
elif [[ "$gen_proof" == "true" ]] && [[ "$(checkgenproof)" == "true" ]]; then
  gen_inclusion
  exit 0
elif [[ "$verify_proof" == "true" ]] && [[ "$(checkverifyproof)" == "true" ]]; then
  verify_correctness
  exit 0
else
  print_usage 
  exit 1 
fi
