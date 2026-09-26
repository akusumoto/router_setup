#!/bin/sh
set -eu

state_dir=/opt/phase3c/performance
state_file="$state_dir/latest"
lock_file=/var/lock/router-performance-hourly.lock
curl_bin=/usr/bin/curl
bytes=25000000
download_url="https://speed.cloudflare.com/__down?bytes=$bytes"
upload_url="https://speed.cloudflare.com/__up"

mkdir -p "$state_dir"
exec 9>"$lock_file"
if ! flock -n 9; then
    exit 0
fi

run_download() {
    "$curl_bin" --ipv4 --connect-timeout 10 --max-time 120 \
        --output /dev/null --silent --show-error \
        --write-out '%{http_code} %{size_download} %{speed_download} %{time_total}' \
        "$download_url"
}

run_upload() {
    dd if=/dev/zero bs=1000000 count=25 2>/dev/null | \
        "$curl_bin" --ipv4 --connect-timeout 10 --max-time 120 \
            --output /dev/null --silent --show-error --data-binary @- \
            --write-out '%{http_code} %{size_upload} %{speed_upload} %{time_total}' \
            "$upload_url"
}

is_decimal() {
    awk -v value="$1" 'BEGIN { exit value ~ /^[0-9]+([.][0-9]+)?$/ ? 0 : 1 }'
}

is_greater() {
    awk -v left="$1" -v right="$2" 'BEGIN { exit left > right ? 0 : 1 }'
}

measure_parallel() {
    direction=$1
    work_dir=$(mktemp -d /tmp/router-performance.XXXXXX)
    pids=""

    for index in 1 2 3; do
        if [ "$direction" = download ]; then
            (
                if run_download > "$work_dir/$index"; then
                    printf '0\n' > "$work_dir/$index.status"
                else
                    printf '1\n' > "$work_dir/$index.status"
                fi
            ) &
        else
            (
                if run_upload > "$work_dir/$index"; then
                    printf '0\n' > "$work_dir/$index.status"
                else
                    printf '1\n' > "$work_dir/$index.status"
                fi
            ) &
        fi
        pids="$pids $!"
    done

    for pid in $pids; do
        wait "$pid" || true
    done

    valid_samples=0
    total_bytes=0
    slowest_seconds=0
    fastest_bps=0
    for index in 1 2 3; do
        result=$(cat "$work_dir/$index" 2>/dev/null || true)
        status=$(cat "$work_dir/$index.status" 2>/dev/null || printf '1')
        set -- $result
        code=${1:-0}
        transferred=${2:-0}
        speed=${3:-0}
        seconds=${4:-0}
        if [ "$status" = 0 ] && [ "$code" = 200 ] && [ "$transferred" = "$bytes" ] \
            && is_decimal "$speed" && is_decimal "$seconds" && is_greater "$seconds" 0; then
            valid_samples=$((valid_samples + 1))
            total_bytes=$((total_bytes + transferred))
            if is_greater "$seconds" "$slowest_seconds"; then
                slowest_seconds=$seconds
            fi
            if is_greater "$speed" "$fastest_bps"; then
                fastest_bps=$speed
            fi
        fi
    done

    rm -f "$work_dir/1" "$work_dir/2" "$work_dir/3" \
        "$work_dir/1.status" "$work_dir/2.status" "$work_dir/3.status"
    rmdir "$work_dir"

    if [ "$valid_samples" -eq 3 ]; then
        aggregate_mbps=$(awk -v bytes="$total_bytes" -v seconds="$slowest_seconds" \
            'BEGIN { printf "%.3f", bytes * 8 / seconds / 1000000 }')
        fastest_mbps=$(awk -v speed="$fastest_bps" \
            'BEGIN { printf "%.3f", speed * 8 / 1000000 }')
        printf '%s %s %s\n' "$valid_samples" "$aggregate_mbps" "$fastest_mbps"
    else
        printf '%s 0 0\n' "$valid_samples"
    fi
}

timestamp=$(date +%s)
set -- $(measure_parallel download)
download_valid_samples=$1
download_aggregate_mbps=$2
download_single_mbps=$3
set -- $(measure_parallel upload)
upload_valid_samples=$1
upload_aggregate_mbps=$2
upload_single_mbps=$3

download_valid=0
upload_valid=0
if [ "$download_valid_samples" -eq 3 ]; then download_valid=1; fi
if [ "$upload_valid_samples" -eq 3 ]; then upload_valid=1; fi

run_success=0
if [ "$download_valid" -eq 1 ] && [ "$upload_valid" -eq 1 ]; then
    run_success=1
fi

tmp_file="$state_file.$$.tmp"
{
    printf 'last_run_timestamp_seconds=%s\n' "$timestamp"
    printf 'download_valid=%s\n' "$download_valid"
    printf 'upload_valid=%s\n' "$upload_valid"
    printf 'download_valid_samples=%s\n' "$download_valid_samples"
    printf 'upload_valid_samples=%s\n' "$upload_valid_samples"
    printf 'run_success=%s\n' "$run_success"
    if [ "$download_valid" -eq 1 ]; then
        printf 'download_aggregate_mbps=%s\n' "$download_aggregate_mbps"
        printf 'download_single_mbps=%s\n' "$download_single_mbps"
    fi
    if [ "$upload_valid" -eq 1 ]; then
        printf 'upload_aggregate_mbps=%s\n' "$upload_aggregate_mbps"
        printf 'upload_single_mbps=%s\n' "$upload_single_mbps"
    fi
} > "$tmp_file"
mv "$tmp_file" "$state_file"
