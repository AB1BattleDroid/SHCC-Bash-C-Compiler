#!/bin/bash

input_source="${2:-/dev/stdin}"
debug=$1
# State tracking
sw_depth=0
sw_id_counter=0
declare -a sw_expr_stack
declare -a sw_id_stack
declare -a pending_cases
declare -a is_first_case

# --- SYMBOL TABLE & TYPEDEFS ---
declare -A symbol_table  # Maps variable name -> type
declare -A typedef_map   # Maps alias -> base type

# Utility: Trim whitespace
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]*}"}"
    echo -n "$var"
}

# Debug helper
debug_var() {
    [[ $debug -gt 0 ]] && echo "/* DEBUG VAR: $1 → type='$2' */" >&2
}

debug_sizeof() {
    [[ $debug -gt 0 ]] && echo "/* DEBUG sizeof: $1 → type='$2' → size=$3 */" >&2
}

debug_line() {
    [[ $debug -gt 0 ]] && echo "/* DEBUG $1 line: $2 */" >&2
}

# Recursively find the base type if a type is an alias
get_base_type() {
    local target="$1"
    while [[ -n "${typedef_map[$target]}" ]]; do
        target="${typedef_map[$target]}"
    done
    echo -n "$target"
}

calc() {
  local type_str="$1"
  [[ "$type_str" == *"*"* ]] && { echo 8; return; }
  local t=0
  for w in $type_str; do
    case "$w" in
      long|double) t=8 ;;
      int|float|unsigned) [[ $t -lt 4 ]] && t=4 ;;
      short) [[ $t -lt 2 ]] && t=2 ;;
      char) [[ $t -lt 1 ]] && t=1 ;;
    esac
  done
  echo ${t:-4}
}

apply_logic_replacements() {
    local line="$1"
    local in_quotes=false
    local pre_char=""

    # Detect if line contains open quotes
    for (( i=0; i<${#line}; i++ )); do
        char="${line:$i:1}"
        if [[ "$char" == "\"" && "$pre_char" != "\\" ]]; then
            if $in_quotes; then in_quotes=false; else in_quotes=true; fi
        fi
        pre_char="$char"
    done

    if $in_quotes; then
        echo "$line"
        return
    fi

    # 1. Substitute typedef aliases
    for alias in "${!typedef_map[@]}"; do
        local pattern="(^|[^a-zA-Z0-9_])$alias($|[^a-zA-Z0-9_])"
        while [[ "$line" =~ $pattern ]]; do
            local prefix="${line%%${BASH_REMATCH[0]}*}"
            local suffix="${line#*${BASH_REMATCH[0]}}"
            line="${prefix}${BASH_REMATCH[1]}${typedef_map[$alias]}${BASH_REMATCH[2]}${suffix}"
        done
    done

    local -a replacements_queue

    # sizeof() evaluation
    while [[ "$line" =~ sizeof\(([^\)]+)\) ]]; do
        local content=$(trim "${BASH_REMATCH[1]}")
        local target_type="$content"

        if [[ -n "${symbol_table[$content]}" ]]; then
            target_type=$(get_base_type "${symbol_table[$content]}")
        fi

        local size_val
        size_val=$(calc "$target_type")

        # DEBUG sizeof
        debug_sizeof "$content" "$target_type" "$size_val"

        local safe_content="$content"
        safe_content="${safe_content//\*/\\*}"
        safe_content="${safe_content//\?/\\?}"
        safe_content="${safe_content//

\[/\

\[}"

        line="${line/sizeof($safe_content)/__SZ_FIX__}"
        replacements_queue+=("$size_val")
    done

    for r in "${replacements_queue[@]}"; do
        line="${line/__SZ_FIX__/$r}"
    done

    while [[ $line =~ (-?[0-9]+)[[:space:]]*(<<=|>>=|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||[+*/%&|^!<>?.:,-])[[:space:]]*(-?[0-9]+) ]] || [[ $line =~ (~|!)[[:space:]]*(-?[0-9]+) ]]; do
        # Binary arithmetic
        while [[ $line =~ (-?[0-9]+)[[:space:]]*(<<=|>>=|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||[+*/%&|^!<>?.:,-])[[:space:]]*(-?[0-9]+) ]]; do
            result=$(( ${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]} ))
            line="${line/${BASH_REMATCH[0]}/$result}"
            while [[ "$line" =~ \($result\) ]]; do
                line="${line/${BASH_REMATCH[0]}/$result}"
            done
        done

        # Unary ops
        while [[ $line =~ (~|!)[[:space:]]*(-?[0-9]+) ]]; do
            op="${BASH_REMATCH[1]}"
            num="${BASH_REMATCH[2]}"

            if [[ $op == "!" ]]; then rep=$(( !num ))
            else rep=$(( ~num ))
            fi

            line="${line/${BASH_REMATCH[0]}/$rep}"
            
            while [[ "$line" =~ \($result\) ]]; do
                line="${line/${BASH_REMATCH[0]}/$result}"
            done
        done
    done

    echo "$line"
}

flush_logic() {
    local depth=$1
    local code=$2
    local indent=$3
    local id=${sw_id_stack[$depth]}
    local expr=${sw_expr_stack[$depth]}

    read -ra vals <<< "${pending_cases[$depth]}"

    for val in "${vals[@]}"; do
        val=$(apply_logic_replacements "$val")

        if [ "${is_first_case[$depth]}" -eq 1 ]; then
            echo "${indent}if ($expr == $val) {"
            is_first_case[$depth]=0
        else
            echo "${indent}} else if ($expr == $val) {"
        fi
        echo "${indent}    $code"
        echo "${indent}    goto _SW${id}_EXIT;"
    done
    pending_cases[$depth]=""
}

while IFS= read -r line || [[ -n "$line" ]]; do

    # Detect function parameters
    if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_[:space:]\*]*[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\((.*)\)[[:space:]]*\{ ]]; then
        params="${BASH_REMATCH[1]}"
        debug_line "parameters" "$params"
        IFS=',' read -ra parts <<< "$params"
        for p in "${parts[@]}"; do
            p=$(trim "$p")
            [[ "$p" == "void" || "$p" == "..." || -z "$p" ]] && continue

            debug_line "param" "$p"

            # Extract type + name
            if [[ "$p" =~ ^(.+[[:space:]\*])([a-zA-Z_][a-zA-Z0-9_]*)$ ]]; then
                p_type=$(trim "${BASH_REMATCH[1]}")
                p_name=$(trim "${BASH_REMATCH[2]}")
                symbol_table["$p_name"]="$p_type"
                debug_var "$p_name" "$p_type"
            fi
        done
    fi

    # Cleanup parens
    while [[ "$line" =~ ^([[:space:]]*)\((.*)\)[[:space:]]*\;?$ ]]; do
        line="${BASH_REMATCH[1]}${BASH_REMATCH[2]};"
    done

    # Typedef
    if [[ "$line" =~ typedef[[:space:]]+(.+)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)\; ]]; then
        real_type=$(trim "${BASH_REMATCH[1]}")
        alias_name=$(trim "${BASH_REMATCH[2]}")
        typedef_map["$alias_name"]="$real_type"
        debug_var "$alias_name" "$real_type"
        line=""
        continue
    fi

    # Variable declaration
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*[\;\=] ]]; then
        v_type=$(trim "${BASH_REMATCH[1]}")
        v_name=$(trim "${BASH_REMATCH[2]}")
        if [[ ! "$v_type" =~ ^(return|case|switch|break)$ ]]; then
            symbol_table["$v_name"]="$v_type"
            debug_var "$v_name" "$v_type"
        fi
    fi

    # Switch start
    if [[ "$line" =~ ^([[:space:]]*)switch[[:space:]]*\((.*)\)[[:space:]]*\{? ]]; then
        ((sw_depth++))
        ((sw_id_counter++))
        indent="${BASH_REMATCH[1]}"
        sw_expr_stack[$sw_depth]=$(trim "${BASH_REMATCH[2]}")
        sw_id_stack[$sw_depth]=$sw_id_counter
        is_first_case[$sw_depth]=1
        pending_cases[$sw_depth]=""
        continue
    fi

    # Case
    if [[ "$line" =~ ^[[:space:]]*case[[:space:]]+([^:]+):(.*) ]]; then
        val=$(trim "${BASH_REMATCH[1]}")
        rem=$(trim "${BASH_REMATCH[2]}")
        pending_cases[$sw_depth]="${pending_cases[$sw_depth]} $val"

        if [[ -n "$rem" && "$rem" != "break;" ]]; then
            flush_logic "$sw_depth" "$rem" "$indent"
        fi
        continue
    fi

    # Default
    if [[ "$line" =~ ^[[:space:]]*default:(.*) ]]; then
        rem=$(trim "${BASH_REMATCH[1]}")
        echo "${indent}} else {"
        [[ -n "$rem" && "$rem" != "break;" ]] && echo "${indent}    $(apply_logic_replacements "$rem")"
        pending_cases[$sw_depth]=""
        continue
    fi

    # Ignore break
    if [[ "$line" =~ ^[[:space:]]*break\; ]]; then
        continue
    fi

    # End of switch
    if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]] && [ $sw_depth -gt 0 ]; then
        echo "${indent}}"
        echo "_SW${sw_id_stack[$sw_depth]}_EXIT: ;"
        ((sw_depth--))
        continue
    fi

    line=$(apply_logic_replacements "$line")

    if [[ $sw_depth -gt 0 ]]; then
        trimmed_line=$(trim "$line")
        if [[ -n "$trimmed_line" ]]; then
            if [[ -n "${pending_cases[$sw_depth]}" ]]; then
                flush_logic "$sw_depth" "$trimmed_line" "$indent"
            else
                echo "${indent}    $trimmed_line"
            fi
        fi
    else
        echo "$line"
    fi

done < "$input_source"
