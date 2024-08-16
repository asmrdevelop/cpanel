draw_line() {
    local max_columns=$(tput cols);
    local columns=${1:-$((max_columns-1))};
    printf '%.s─' $(seq 1 ${columns});
    printf "\n";
}

export RED=$(tput setaf 1 :-"" 2>/dev/null)
export GREEN=$(tput setaf 2 :-"" 2>/dev/null)
export YELLOW=$(tput setaf 3 :-"" 2>/dev/null)
export BLUE=$(tput setaf 4 :-"" 2>/dev/null)
export RESET=$(tput sgr0 :-"" 2>/dev/null)