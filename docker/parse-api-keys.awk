#!/bin/sh
# Prints "<token><TAB><role>" for each api_keys entry of a uni-api YAML config.
# Reads through getline so it works on any awk implementation and stays free of
# a YAML dependency in the runtime image.
set -eu
awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function strip(s) {
        s = trim(s)
        if (substr(s, 1, 1) == SQ) s = substr(s, 2)
        if (substr(s, length(s), 1) == SQ) s = substr(s, 1, length(s) - 1)
        if (substr(s, 1, 1) == DQ) s = substr(s, 2)
        if (substr(s, length(s), 1) == DQ) s = substr(s, 1, length(s) - 1)
        return s
    }
    function value(line,   i) {
        i = index(line, ":")
        return strip(substr(line, i + 1))
    }
    function emit() {
        if (started && token != "") printf "%s%s%s%s", token, TAB, role, NL
        token = ""
        role = ""
    }
    BEGIN {
        SQ = sprintf("%c", 39); DQ = sprintf("%c", 34)
        TAB = sprintf("%c", 9); NL = sprintf("%c", 10)
        while ((getline line < ARGV[1]) > 0) {
            if (!in_keys) {
                if (line ~ /^api_keys:[ \t]*$/) in_keys = 1
                continue
            }
            # Any non-indented line ends the api_keys block.
            if (line ~ /^[^ \t#]/) break
            # A new list item starts a candidate entry.
            if (line ~ /^[ \t]+-[ \t]+[a-zA-Z_]+:/) {
                emit()
                started = 1
                rest = line
                sub(/^[ \t]+-[ \t]+/, "", rest)
                if (rest ~ /^api:/) token = value(rest)
                if (rest ~ /^role:/) role = value(rest)
                continue
            }
            if (!started) continue
            if (token == "" && line ~ /^[ \t]+api:/) { token = value(line); continue }
            if (role == "" && line ~ /^[ \t]+role:/) { role = value(line); continue }
        }
        emit()
        exit
    }
' "$1"
