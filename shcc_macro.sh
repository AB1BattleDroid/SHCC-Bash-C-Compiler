#!/bin/bash
source_file="$1"
debug="$2"
[[ -n $debug ]] && debug=false 

# 1. SETUP PATHS
if [[ "$0" == *"/"* ]]; then script_dir="${0%/*}"; else script_dir="."; fi
include_dir="$script_dir/Include"
search_paths=("$PWD")

# 2. GLOBAL STATE
macro_names=()
macro_values=()
processing_stack=()

# Initial Macros - Logic updated to match your architecture detection
case "$(uname -ms)" in
    "Linux x86_64"|"Linux amd64")
        macro_names+=("__x86_64__" "__amd64__" "__LP64__" "__linux__" "__unix__")
        macro_values+=("1" "1" "1" "1" "1") ;;
    "Linux aarch64"|"Linux arm64")
        macro_names+=("__aarch64__" "__arm64__" "__linux__" "__unix__" "__LP64__")
        macro_values+=("1" "1" "1" "1" "1") ;;
    Darwin*)
        macro_names+=("__APPLE__" "__MACH__" "__unix__")
        macro_values+=("1" "1" "1")
        [[ "$(uname -m)" == "arm64" ]] && macro_names+=("__aarch64__" "__arm64__" "__LP64__") && macro_values+=("1" "1" "1")
        [[ "$(uname -m)" == "x86_64" ]] && macro_names+=("__x86_64__" "__LP64__") && macro_values+=("1" "1") ;;
    *) macro_names+=("__unix__"); macro_values+=("1") ;;
esac

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}
bash_sed() {
    local str="$1"
    local search="$2"
    local replace="$3"
    local result=""
    # Boundary: (Start or non-word) + SEARCH + (non-word or End)
    local re="(^|[^A-Za-z0-9_])($search)([^A-Za-z0-9_]|$)"

    while [[ "$str" =~ $re ]]; do
        local pre="${str%%"${BASH_REMATCH[0]}"*}"
        local leading="${BASH_REMATCH[1]}"
        local trailing="${BASH_REMATCH[3]}"
        
        # Build result using the leading boundary
        result+="${pre}${leading}${replace}"
        
        # KEY: We put 'trailing' back at the start of the string for the next pass
        # This allows ",NULL," to match both boundaries correctly
        str="${trailing}${str#*"${BASH_REMATCH[0]}"}"
    done
    printf '%s' "${result}${str}"
}
expand_func_macro() {
    local body="$1" def_args="$2" call_args="$3"
    IFS=',' read -r -a d_arr <<< "$def_args"
    IFS=',' read -r -a c_arr <<< "$call_args"
    
    local expanded="$body"
    for i in "${!d_arr[@]}"; do
        local param=$(trim "${d_arr[$i]}")
        local val=$(trim "${c_arr[$i]}")
        [[ -z "$param" ]] && continue
        
        # Call our sed-based function
        expanded=$(bash_sed "$expanded" "$param" "$val")
    done
    printf '%s' "$expanded"
}
process_file() {
    local target="$1"
    [[ ! -f "$target" ]] && return
    for f in "${processing_stack[@]}"; do [[ "$f" == "$target" ]] && return; done
    processing_stack+=("$target")

    local line ignore=false depth=0 
    local active=(true) satisfied=(false)
    local -a lines
    mapfile -t lines < "$target"

    local idx total_lines=${#lines[@]}
    for (( idx=0; idx<total_lines; idx++ )); do
        line="${lines[$idx]//$'\r'/}"

        # --- 1. MULTI-LINE & COMMENTS ---
        while [[ "$line" == *"\\" ]]; do
            line="${line%\\}"; ((idx++))
            (( idx < total_lines )) && line+="${lines[$idx]//$'\r'/}" || break
        done
        [[ $ignore == true && "$line" == *"*/"* ]] && { line="${line#*\*\/}"; ignore=false; }
        [[ $ignore == true ]] && continue
        if [[ "$line" == *"/*"* ]]; then
            if [[ "$line" == *"*/"* ]]; then line="${line%%/\**}${line#*\*\/}"; else line="${line%%/\**}"; ignore=true; fi
        fi
        [[ "$line" == *"//"* ]] && line="${line%%//*}"
        [[ -z "${line//[[:space:]]/}" ]] && continue
        
        # --- 2. DIRECTIVES (#if, #elif, etc) ---
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*(ifn?def|if|elif|else|endif|define|include|error|warning)([[:space:]]+(.*))? ]]; then
            local dir="${BASH_REMATCH[1]}" expr="${BASH_REMATCH[3]}"
            
            case "$dir" in
                if*|elif*)
                    # 1. Update Global Depth
                    if [[ "$dir" == "if"* ]]; then
                        ((depth++))
                        satisfied[$depth]=false
                    fi
                    
                    # 2. Inherit Parent State (Force look at the level above)
                    local p_depth=$((depth - 1))
                    local p_active="true"
                    if [[ $p_depth -gt 0 ]]; then
                        p_active=${active[$p_depth]}
                    fi

                    $debug && echo "//DEBUG: L$idx: [$dir] Depth:$depth ParentActive:$p_active PrevSat:${satisfied[$depth]}" >&2

                    # 3. Decision Gate
                    if [[ "$p_active" != "true" || ( "$dir" == "elif" && "${satisfied[$depth]}" == "true" ) ]]; then
                        active[$depth]="false"
                        $debug && echo "//DEBUG: L$idx:   -> Block forced FALSE (Parent:$p_active Sat:${satisfied[$depth]})" >&2
                        continue
                    fi

                    local eval_expr=" $expr "
                    $debug && echo "//DEBUG: L$idx:   -> Raw Expression: '$expr'" >&2
                    
                    # 4. Expand defined(X) with Macro Dump
                    local def_re="defined\(([A-Za-z0-9_]+)\)"
                    while [[ "$eval_expr" =~ $def_re ]]; do
                        local m_target="${BASH_REMATCH[1]}"
                        local found=0
                        # Debug: Optional dump of all macros for this specific check
                        # echo "DEBUG: Looking for '$m_target' in: ${macro_names[*]}" >&2
                        for m in "${macro_names[@]}"; do
                            if [[ "${m%%(*}" == "$m_target" ]]; then found=1; break; fi
                        done
                        $debug && echo "//DEBUG: L$idx:     [defined] Check '$m_target' -> $found" >&2
                        eval_expr="${eval_expr//"${BASH_REMATCH[0]}"/$found}"
                    done

                    # 5. Expand other Macros
                    for (( m_i=${#macro_names[@]}-1; m_i>=0; m_i-- )); do
                        local m_name="${macro_names[$m_i]%%(*}"
                        [[ -z "$m_name" || "$eval_expr" != *"$m_name"* ]] && continue
                        eval_expr=$(bash_sed "$eval_expr" "$m_name" "${macro_values[$m_i]}")
                    done

                    # 6. Math Evaluation
                    eval_expr="${eval_expr//[A-Za-z_][A-Za-z0-9_]*/0}"
                    local clean_math="${eval_expr//[!0-9+*-<>|&!^() ]/}"
                    
                    local res=0
                    if [[ "$dir" == "ifndef" ]]; then
                        local f=0; for m in "${macro_names[@]}"; do [[ "${m%%(*}" == "$expr" ]] && f=1 && break; done
                        [[ $f -eq 0 ]] && res=1
                    elif [[ "$dir" == "ifdef" ]]; then
                        for m in "${macro_names[@]}"; do [[ "${m%%(*}" == "$expr" ]] && res=1 && break; done
                    else
                        if (( clean_math )); then res=1; fi 2>/dev/null
                    fi

                    # 7. Finalize Global State
                    if [[ $res -ne 0 ]]; then
                        active[$depth]="true"
                        satisfied[$depth]="true"
                    else
                        active[$depth]="false"
                    fi
                    
                    $debug && echo "//DEBUG: L$idx:   -> Math: '$clean_math' -> Result:$res -> Set Active Depth $depth: ${active[$depth]}" >&2
                    ;;
                else*)
                    if [[ "$dir" == "else" ]]; then
                        local p_active="true"
                        [[ $((depth-1)) -gt 0 ]] && p_active=${active[$((depth-1))]}
                        
                        if [[ "$p_active" == "true" && "${satisfied[$depth]}" == "false" ]]; then
                            active[$depth]="true"
                            satisfied[$depth]="true"
                        else
                            active[$depth]="false"
                        fi 
                    fi
                    ;;
                endif*)
                    # This is the endif - Clear the level before popping
                    active[$depth]="true"
                    satisfied[$depth]="false"
                    ((depth--)) 
                    ;;
                define)
                    # 1. Extract the name (everything up to the first space or paren)
                    local name="${expr%%[[:space:](]*}"
                    local rest=$(trim "${expr#$name}")

                    if [[ "$expr" == *"$name("* ]]; then
                        # 2. Function-like macro: #define MACRO(x) ...
                        # Ensure there is NO space between name and '('
                        local func_args="${expr#*(}"
                        func_args="${func_args%%)*}"
                        local func_body=$(trim "${expr#*)}")
                        macro_names+=("$name($func_args)")
                        macro_values+=("$func_body")
                    else
                        # 3. Object-like macro: #define NULL ((void*)0)
                        macro_names+=("$name")
                        macro_values+=("$rest")
                    fi 
                    ;;
                include)
                    local inc=$(echo "$expr" | tr -d '"<>')
                    local f_p=""
                    [[ -f "$include_dir/$inc" ]] && f_p="$include_dir/$inc"
                    for p in "${search_paths[@]}"; do [[ -z "$f_p" && -f "$p/$inc" ]] && f_p="$p/$inc"; done
                    [[ -n "$f_p" ]] && process_file "$f_p" ;;
                error|warning) 
                    if [[ ${active[$depth]} == true ]]; then
                        printf '[%s]: %s\n' "${dir^^}" "$expr" >&2
                        [[ "$dir" == "error" ]] && exit 1
                    fi ;;
            esac
            continue
        fi

        # --- 3. CODE LINE EXPANSION ---
        if [[ ${active[$depth]} == true ]]; then
            # 1. Protect string literals to avoid expanding macros inside quotes
            declare -a saved_strs=()
            local s_idx=0
            while [[ "$line" =~ \"([^\"\\]|\\.)*\" ]]; do
                saved_strs+=("${BASH_REMATCH[0]}")
                line="${line/"${BASH_REMATCH[0]}"/__STR_LIT_${s_idx}__}"
                ((s_idx++))
            done

            if [[ "$line" =~ [a-zA-Z_] ]]; then
                local changed=true
                local safety=0
                
                # Outer loop: Keep expanding until no more macros are found
                while [[ "$changed" == true && $safety -lt 30 ]]; do
                    changed=false
                    ((safety++))
                    
                    # Inner loop: Iterate through all defined macros
                    for (( m_idx=${#macro_names[@]}-1; m_idx>=0; m_idx-- )); do
                        local m_full="${macro_names[$m_idx]}"
                        local m_name="${m_full%%(*}"
                        
                        # Quick skip if the macro name isn't present in the line
                        [[ "$line" != *"$m_name"* ]] && continue 
                        
                        local val="${macro_values[$m_idx]}"

                        if [[ "$m_full" == *"("* ]]; then
                            # --- Function-like expansion (e.g., va_start) ---
                            local def_args="${m_full#*(}"; def_args="${def_args%)}"
                            local m_esc=$(printf '%s' "$m_name" | sed 's/[^^a-zA-Z0-9_]/\\&/g')
                            local func_re="(^|[^A-Za-z0-9_])$m_esc\(([^)]*)\)"
                            
                            if [[ "$line" =~ $func_re ]]; then
                                local lead="${BASH_REMATCH[1]}"
                                local args="${BASH_REMATCH[2]}"
                                local expanded=$(expand_func_macro "$val" "$def_args" "$args")
                                line="${line//"${BASH_REMATCH[0]}"/"$lead$expanded"}"
                            fi
                        else
                            # --- Object-like expansion (e.g., NULL, STDOUT_FILENO) ---
                            line=$(bash_sed "$line" "$m_name" "$val")
                        fi
                    done
                done
            fi

            # 2. Restore string literals
            for (( i=0; i<${#saved_strs[@]}; i++ )); do
                line="${line/__STR_LIT_${i}__/${saved_strs[$i]}}"
            done
            
            # Final output of the preprocessed line
            printf '%s\n' "$line"
        fi
    done
    unset 'processing_stack[-1]'
}

process_file "$source_file"

! $debug && exit
for I in "${!macro_values[@]}"; do
    echo "//term ${macro_names[I]} defined as ${macro_values[I]}"
done