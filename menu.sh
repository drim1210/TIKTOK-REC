#!/bin/bash
cd "$(dirname "$0")" || exit 1
WATCHLIST="watchlist.txt"
CONFIG_FILE="autoconfig.txt"
USER_CONFIG_FILE="user_config.txt"
SESSION="tiktok"
MANUAL_SESSION="tiktok_manual"
touch "$WATCHLIST"
touch "$CONFIG_FILE"
touch "$USER_CONFIG_FILE"

pause() { echo ""; read -rp "Bấm Enter để quay lại menu..." _; }

get_config() {
    local key="$1" default="$2" val
    val=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2)
    if [ -n "$val" ]; then echo "$val"; else echo "$default"; fi
}

set_config() {
    local key="$1" value="$2"
    touch "$CONFIG_FILE"
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

get_user_field() {
    local uname="$1" field_index="$2" default="$3" line val
    line=$(grep "^${uname}|" "$USER_CONFIG_FILE" 2>/dev/null | tail -1)
    if [ -z "$line" ]; then echo "$default"; return; fi
    val=$(echo "$line" | cut -d'|' -f"$field_index")
    if [ -z "$val" ]; then echo "$default"; else echo "$val"; fi
}

get_user_telegram() { get_user_field "$1" 2 "$(get_config TELEGRAM off)"; }
get_user_interval() { get_user_field "$1" 3 "$(get_config INTERVAL 5)"; }
get_user_schedule() { get_user_field "$1" 4 "0"; }

set_user_config() {
    local uname="$1" tg="$2" interval="$3" schedule="$4"
    touch "$USER_CONFIG_FILE"
    grep -v "^${uname}|" "$USER_CONFIG_FILE" > "${USER_CONFIG_FILE}.tmp" 2>/dev/null
    mv "${USER_CONFIG_FILE}.tmp" "$USER_CONFIG_FILE"
    echo "${uname}|${tg}|${interval}|${schedule}" >> "$USER_CONFIG_FILE"
}

build_user_command() {
    local uname="$1" tg interval schedule TG_FLAG
    tg=$(get_user_telegram "$uname")
    interval=$(get_user_interval "$uname")
    schedule=$(get_user_schedule "$uname")
    TG_FLAG=""
    if [ "$tg" = "on" ]; then TG_FLAG="-telegram"; fi
    if [ -n "$schedule" ] && [ "$schedule" != "0" ]; then
        echo "bash $(pwd)/watch_and_record.sh \"$uname\" \"$TG_FLAG\" \"$interval\" \"$schedule\" \"5\""
    else
        echo "uv run python src/main.py -user $uname -mode automatic -output ~/recordings $TG_FLAG -automatic_interval $interval -no-update-check"
    fi
}

start_single_user_window() {
    local uname="$1" CMD
    CMD=$(build_user_command "$uname")
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        if ! tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qxF "$uname"; then
            tmux new-window -t "$SESSION" -n "$uname" "cd $(pwd) && $CMD"
        fi
    else
        tmux new -d -s "$SESSION" -n "$uname" "cd $(pwd) && $CMD"
    fi
}

start_auto_sessions() {
    local CMD first
    first=true
    while IFS= read -r uname; do
        [ -z "$uname" ] && continue
        CMD=$(build_user_command "$uname")
        if $first; then
            tmux new -d -s "$SESSION" -n "$uname" "cd $(pwd) && $CMD"
            first=false
        else
            tmux new-window -t "$SESSION" -n "$uname" "cd $(pwd) && $CMD"
        fi
    done < "$WATCHLIST"
}

graceful_stop_window() {
    local uname="$1" leftover_pids
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qxF "$uname"; then
            tmux send-keys -t "${SESSION}:${uname}" C-c 2>/dev/null
            echo "Da gui Ctrl+C cho $uname, dang cho luu/convert file (5s)..."
            sleep 5
            tmux kill-window -t "${SESSION}:${uname}" 2>/dev/null
        fi
    fi
    sleep 1
    leftover_pids=$(pgrep -f "src/main.py -user ${uname} " 2>/dev/null)
    if [ -n "$leftover_pids" ]; then
        echo "Phat hien tien trinh con sot lai cho $uname, dang dung han..."
        kill $leftover_pids 2>/dev/null
        sleep 1
        kill -9 $leftover_pids 2>/dev/null
    fi
}

graceful_stop_session() {
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "Dang dung an toan tat ca tien trinh (luu file dang ghi do truoc khi restart)..."
        while IFS= read -r wname; do
            [ -z "$wname" ] && continue
            tmux send-keys -t "${SESSION}:${wname}" C-c 2>/dev/null
        done < <(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null)
        sleep 5
        tmux kill-session -t "$SESSION" 2>/dev/null
    fi
}

get_recording_elapsed() {
    local uname="$1" latest mtime now diff bn ts date_part time_part date_fmt time_fmt start_epoch elapsed
    latest=$(ls -t ~/recordings/TK_${uname}_*_flv.mp4 2>/dev/null | head -1)
    if [ -z "$latest" ]; then echo ""; return; fi
    mtime=$(stat -c %Y "$latest" 2>/dev/null)
    now=$(date +%s)
    if [ -z "$mtime" ]; then echo ""; return; fi
    diff=$((now - mtime))
    if [ "$diff" -gt 3600 ]; then echo ""; return; fi
    bn="${latest##*/}"
    ts="${bn#TK_${uname}_}"
    ts="${ts%_flv.mp4}"
    date_part="${ts%_*}"
    time_part="${ts##*_}"
    date_fmt="${date_part//./-}"
    time_fmt="${time_part//-/:}"
    start_epoch=$(date -d "${date_fmt} ${time_fmt}" +%s 2>/dev/null)
    if [ -n "$start_epoch" ]; then
        elapsed=$((now - start_epoch))
        printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))
    else
        echo "?"
    fi
}

get_recording_users() {
    local uname elapsed result=""
    if [ ! -s "$WATCHLIST" ]; then echo ""; return; fi
    while IFS= read -r uname; do
        [ -z "$uname" ] && continue
        elapsed=$(get_recording_elapsed "$uname")
        if [ -n "$elapsed" ]; then result="$result $uname"; fi
    done < "$WATCHLIST"
    echo "$result" | sed 's/^ //'
}

manage_watchlist() {
    while true; do
        clear
        echo "===== DANH SÁCH THEO DÕI (watchlist) ====="
        if [ -s "$WATCHLIST" ]; then
            nl -w2 -s". " "$WATCHLIST"
        else
            echo "(Chưa có username nào)"
        fi
        echo "==========================================="
        echo "1. Thêm username"
        echo "2. Xóa username"
        echo "0. Quay lại"
        read -rp "Chọn: " c
        case $c in
            1)
                read -rp "Nhập username muốn theo dõi (không @): " uname
                if [ -z "$uname" ]; then
                    echo "Bỏ trống, không thêm."
                elif grep -qxF "$uname" "$WATCHLIST"; then
                    echo "Đã có trong danh sách rồi."
                else
                    echo "Đang kiểm tra username có tồn tại không..."
                    result=$(uv run python check_user.py "$uname" 2>/dev/null | tail -1)
                    force=""
                    if [ "$result" = "NOT_FOUND" ]; then
                        echo "Username '$uname' KHONG ton tai tren TikTok."
                        read -rp "Van muon them vao danh sach? (y/n): " force
                    elif [ "$result" = "EXISTS" ]; then
                        echo "Username '$uname' hop le."
                        force="y"
                    else
                        echo "Khong xac nhan duoc (mang loi hoac TikTok chan kiem tra)."
                        read -rp "Van muon them vao danh sach? (y/n): " force
                    fi
                    if [ "$force" = "y" ] || [ "$force" = "Y" ]; then
                        echo "$uname" >> "$WATCHLIST"
                        echo "Da them: $uname"
                        if tmux has-session -t "$SESSION" 2>/dev/null; then
                            start_single_user_window "$uname"
                            echo "Auto dang BAT, da tu dong bat ghi cho $uname luon."
                        fi
                    else
                        echo "Da huy."
                    fi
                fi
                pause ;;
            2)
                if [ ! -s "$WATCHLIST" ]; then echo "Danh sách trống."; pause; continue; fi
                nl -w2 -s". " "$WATCHLIST"
                read -rp "Nhập số dòng muốn xóa: " num
                if [[ "$num" =~ ^[0-9]+$ ]]; then
                    target_user=$(sed -n "${num}p" "$WATCHLIST")
                    sed -i "${num}d" "$WATCHLIST"
                    echo "Đã xóa dòng $num ($target_user)."
                    if [ -n "$target_user" ]; then
                        echo "Dang dung ghi cho $target_user (neu co)..."
                        graceful_stop_window "$target_user"
                        echo "Da dam bao $target_user khong con ghi nua."
                    fi
                else
                    echo "Số không hợp lệ."
                fi
                pause ;;
            0) return ;;
            *) echo "Không hợp lệ."; pause ;;
        esac
    done
}

auto_settings_menu() {
    while true; do
        clear
        local auto_status telegram_cfg interval_cfg
        if tmux has-session -t "$SESSION" 2>/dev/null; then auto_status="BAT"; else auto_status="TAT"; fi
        telegram_cfg=$(get_config TELEGRAM off)
        interval_cfg=$(get_config INTERVAL 5)
        echo "===== CAI DAT AUTO-GHI (MAC DINH CHUNG) ====="
        echo "1. Bat/Tat AUTO         [hien tai: $auto_status]"
        echo "2. Bat/Tat Upload Tele  [hien tai: $telegram_cfg]"
        echo "3. Chu ky kiem tra live [hien tai: ${interval_cfg} phut]"
        echo "0. Quay lai"
        echo "(Muon chinh rieng tung user, vao muc 5 o menu chinh)"
        echo "==============================================="
        read -rp "Chon: " c
        case $c in
            1)
                if tmux has-session -t "$SESSION" 2>/dev/null; then
                    rec_users=$(get_recording_users)
                    if [ -n "$rec_users" ]; then
                        echo "!!! Dang co nguoi ghi live:$rec_users"
                        echo "Se tu dong luu file cua ho truoc khi tat (an toan)."
                    fi
                    read -rp "Auto dang BAT. Xac nhan TAT? (y/n): " ans
                    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                        graceful_stop_session
                        echo "Da TAT auto-ghi."
                    fi
                else
                    if [ ! -s "$WATCHLIST" ]; then
                        echo "Danh sach theo doi dang trong."
                    else
                        start_auto_sessions
                        echo "Da BAT auto-ghi cho toan bo danh sach."
                    fi
                fi
                pause ;;
            2)
                current=$(get_config TELEGRAM off)
                if [ "$current" = "on" ]; then new="off"; else new="on"; fi
                set_config TELEGRAM "$new"
                echo "Da chuyen Upload Telegram MAC DINH sang: $new"
                echo "(Chi ap dung cho user chua duoc chinh rieng)"
                if tmux has-session -t "$SESSION" 2>/dev/null; then
                    rec_users=$(get_recording_users)
                    if [ -n "$rec_users" ]; then
                        echo "!!! Dang co nguoi ghi live:$rec_users"
                    fi
                    read -rp "Khoi dong lai toan bo de ap dung ngay? (y/n): " ans
                    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                        graceful_stop_session
                        start_auto_sessions
                        echo "Da khoi dong lai voi cai dat moi."
                    fi
                fi
                pause ;;
            3)
                read -rp "Nhap chu ky kiem tra moi (phut): " val
                if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ]; then
                    set_config INTERVAL "$val"
                    echo "Da luu chu ky mac dinh: $val phut."
                    if tmux has-session -t "$SESSION" 2>/dev/null; then
                        rec_users=$(get_recording_users)
                        if [ -n "$rec_users" ]; then
                            echo "!!! Dang co nguoi ghi live:$rec_users"
                        fi
                        read -rp "Khoi dong lai toan bo de ap dung ngay? (y/n): " ans
                        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                            graceful_stop_session
                            start_auto_sessions
                            echo "Da khoi dong lai voi chu ky moi."
                        fi
                    fi
                else
                    echo "Gia tri khong hop le."
                fi
                pause ;;
            0) return ;;
            *) echo "Khong hop le."; pause ;;
        esac
    done
}

record_one_user_now() {
    read -rp "Nhập username TikTok (không @): " uname
    if [ -z "$uname" ]; then echo "Username không được để trống."; pause; return; fi
    if tmux has-session -t "$MANUAL_SESSION" 2>/dev/null && tmux list-windows -t "$MANUAL_SESSION" -F '#{window_name}' 2>/dev/null | grep -qxF "$uname"; then
        echo "Đã có 1 phiên ghi thủ công cho $uname đang chạy rồi."
        pause
        return
    fi
    read -rp "Bật upload Telegram? (y/n): " tg
    TG_FLAG=""
    if [ "$tg" = "y" ] || [ "$tg" = "Y" ]; then TG_FLAG="-telegram"; fi
    CMD="uv run python src/main.py -user $uname -output ~/recordings $TG_FLAG -no-update-check"
    if tmux has-session -t "$MANUAL_SESSION" 2>/dev/null; then
        tmux new-window -t "$MANUAL_SESSION" -n "$uname" "cd $(pwd) && $CMD"
    else
        tmux new -d -s "$MANUAL_SESSION" -n "$uname" "cd $(pwd) && $CMD"
    fi
    echo "Đã bắt đầu ghi nền cho $uname (không cần giữ SSH mở)."
    echo "Dùng mục 'Dừng ghi thủ công' để dừng/kiểm tra sau."
    pause
}

stop_manual_recording() {
    if ! tmux has-session -t "$MANUAL_SESSION" 2>/dev/null; then
        echo "Hiện không có phiên ghi thủ công nào đang chạy."
        pause
        return
    fi
    mapfile -t wins < <(tmux list-windows -t "$MANUAL_SESSION" -F '#{window_name}' 2>/dev/null)
    if [ ${#wins[@]} -eq 0 ]; then
        echo "Hiện không có phiên ghi thủ công nào đang chạy."
        pause
        return
    fi
    clear
    echo "===== CÁC PHIÊN GHI THỦ CÔNG (ngoài danh sách theo dõi) ====="
    for i in "${!wins[@]}"; do
        elapsed=$(get_recording_elapsed "${wins[$i]}")
        if [ -n "$elapsed" ]; then
            echo "$((i+1)). ${wins[$i]} (đang ghi $elapsed)"
        else
            echo "$((i+1)). ${wins[$i]} (đang chờ / không rõ trạng thái)"
        fi
    done
    echo "0. Quay lại"
    read -rp "Chọn số để dừng ghi: " sel
    if [ "$sel" = "0" ] || [ -z "$sel" ]; then return; fi
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#wins[@]}" ]; then
        target="${wins[$((sel-1))]}"
        tmux send-keys -t "${MANUAL_SESSION}:${target}" C-c 2>/dev/null
        echo "Đã gửi lệnh dừng ghi cho $target, file đang được lưu/convert."
    else
        echo "Lựa chọn không hợp lệ."
    fi
    pause
}

record_menu() {
    while true; do
        clear
        echo "===== GHI LIVE THỦ CÔNG (ngoài danh sách theo dõi) ====="
        echo "1. Ghi live 1 user NGAY (chạy nền, không cần giữ SSH)"
        echo "2. Dừng 1 phiên ghi thủ công đang chạy"
        echo "0. Quay lại"
        read -rp "Chọn: " c
        case $c in
            1) record_one_user_now ;;
            2) stop_manual_recording ;;
            0) return ;;
            *) echo "Không hợp lệ."; pause ;;
        esac
    done
}

list_and_manage_recordings() {
    while true; do
        clear
        echo "--- Video trong ~/recordings ---"
        mapfile -t files < <(ls -1t ~/recordings/*.mp4 2>/dev/null)
        if [ ${#files[@]} -eq 0 ]; then
            echo "(Không có video nào)"
            pause
            return
        fi
        for i in "${!files[@]}"; do
            size=$(du -h "${files[$i]}" 2>/dev/null | cut -f1)
            echo "$((i+1)). $(basename "${files[$i]}") ($size)"
        done
        echo ""
        du -sh ~/recordings 2>/dev/null
        echo ""
        echo "1. Upload 1 video lên Telegram"
        echo "2. Xóa 1 video"
        echo "3. Xóa TOÀN BỘ video"
        echo "0. Quay lại"
        read -rp "Chọn: " act

        case "$act" in
            1)
                read -rp "Nhập số video muốn upload: " sel
                if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#files[@]}" ]; then
                    target="${files[$((sel-1))]}"
                    echo "Đang upload: $(basename "$target")"
                    uv run python upload_video.py "$target"
                    read -rp "Xóa file này sau khi đã upload? (y/n): " delafter
                    if [ "$delafter" = "y" ] || [ "$delafter" = "Y" ]; then
                        rm -f "$target"
                        echo "Đã xóa: $(basename "$target")"
                    fi
                else
                    echo "Số không hợp lệ."
                fi
                pause
                ;;
            2)
                read -rp "Nhập số video muốn xóa: " sel
                if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#files[@]}" ]; then
                    target="${files[$((sel-1))]}"
                    read -rp "Xác nhận xóa $(basename "$target")? (y/n): " ans
                    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                        rm -f "$target"
                        echo "Đã xóa: $(basename "$target")"
                    fi
                else
                    echo "Số không hợp lệ."
                fi
                pause
                ;;
            3)
                read -rp "XÁC NHẬN xóa TOÀN BỘ video? Gõ 'yes': " confirm
                if [ "$confirm" = "yes" ]; then
                    rm -rf ~/recordings/*
                    echo "Đã xóa toàn bộ."
                else
                    echo "Đã hủy."
                fi
                pause
                ;;
            0|"")
                return
                ;;
            *)
                echo "Không hợp lệ."
                pause
                ;;
        esac
    done
}


edit_user_config() {
    local uname="$1" tg interval schedule

    while true; do
        clear
        tg=$(get_user_telegram "$uname")
        interval=$(get_user_interval "$uname")
        schedule=$(get_user_schedule "$uname")

        echo "===== CAU HINH RIENG: $uname ====="
        echo "1. Upload Telegram      [hien tai: $tg]"
        echo "2. Chu ky kiem tra live [hien tai: ${interval} phut]"
        echo "3. Hen gio ghi toi da   [hien tai: $([ "$schedule" = "0" ] && echo 'khong gioi han' || echo "${schedule} phut")]"
        echo "0. Quay lai"
        echo "==================================="

        read -rp "Chon: " c

        case $c in
            1)
                if [ "$tg" = "on" ]; then
                    new_tg="off"
                else
                    new_tg="on"
                fi
                set_user_config "$uname" "$new_tg" "$interval" "$schedule"
                echo "Da doi Upload Telegram cua $uname sang: $new_tg"
                ;;
            2)
                read -rp "Nhap chu ky kiem tra moi (phut): " val
                if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ]; then
                    set_user_config "$uname" "$tg" "$val" "$schedule"
                    echo "Da luu chu ky rieng cho $uname: $val phut."
                else
                    echo "Gia tri khong hop le."
                fi
                ;;
            3)
                echo "Hen gio: ghi toi da bao nhieu phut roi tu dong dung + luu."
                echo "Sau khi het gio, se cho 5 tieng roi moi kiem tra lai user nay."
                echo "Nhap 0 = khong gioi han (ghi binh thuong nhu truoc)."
                read -rp "Nhap so phut hen gio: " val

                if [[ "$val" =~ ^[0-9]+$ ]]; then
                    set_user_config "$uname" "$tg" "$interval" "$val"
                    if [ "$val" = "0" ]; then
                        echo "Da tat hen gio cho $uname (ghi binh thuong)."
                    else
                        echo "Da dat hen gio cho $uname: toi da $val phut/lan ghi."
                    fi
                else
                    echo "Gia tri khong hop le."
                fi
                ;;
            0)
                return
                ;;
            *)
                echo "Khong hop le."
                pause
                continue
                ;;
        esac

        if tmux has-session -t "$SESSION" 2>/dev/null && \
           tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qxF "$uname"; then

            elapsed=$(get_recording_elapsed "$uname")

            if [ -n "$elapsed" ]; then
                echo "!!! $uname dang ghi live ($elapsed). Khong nen khoi dong lai ngay bay gio."
                read -rp "Van muon khoi dong lai rieng $uname de ap dung ngay? (y/n): " ans
            else
                read -rp "Khoi dong lai rieng $uname de ap dung ngay? (y/n): " ans
            fi

            if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                graceful_stop_window "$uname"
                start_single_user_window "$uname"
                echo "Da khoi dong lai $uname voi cau hinh moi."
            fi
        fi

        pause
    done
}


show_status_and_control() {
    clear
    echo "===== TRẠNG THÁI CHI TIẾT ====="
    if [ ! -s "$WATCHLIST" ]; then
        echo "(Danh sách theo dõi đang trống)"
        pause
        return
    fi
    local i=1
    declare -A idx_to_user
    declare -A idx_to_elapsed
    while IFS= read -r uname; do
        [ -z "$uname" ] && continue
        if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qxF "$uname"; then
            auto_display="on"
        else
            auto_display="off"
        fi
        tg=$(get_user_telegram "$uname")
        interval=$(get_user_interval "$uname")
        schedule=$(get_user_schedule "$uname")
        sched_display="khong gioi han"
        if [ "$schedule" != "0" ]; then sched_display="${schedule}p/lan"; fi
        elapsed=$(get_recording_elapsed "$uname")
        idx_to_user[$i]="$uname"
        idx_to_elapsed[$i]="$elapsed"
        if [ -n "$elapsed" ]; then
            printf "%d. %-18s (DANG GHI %-10s): auto:%-3s upload:%-3s check:%sp hen:%s\n" "$i" "$uname" "$elapsed" "$auto_display" "$tg" "$interval" "$sched_display"
        else
            printf "%d. %-18s (dang cho live): auto:%-3s upload:%-3s check:%sp hen:%s\n" "$i" "$uname" "$auto_display" "$tg" "$interval" "$sched_display"
        fi
        i=$((i+1))
    done < "$WATCHLIST"
    echo "================================"
    echo "1. Dừng ghi 1 user (chọn số)"
    echo "2. Dừng TOÀN BỘ auto"
    echo "3. Sửa cấu hình riêng 1 user (upload/chu ky/hen gio)"
    echo "0. Quay lại"
    read -rp "Chọn: " action
    case "$action" in
        1)
            read -rp "Nhập số user muốn dừng ghi: " sel
            if [[ "$sel" =~ ^[0-9]+$ ]] && [ -n "${idx_to_user[$sel]}" ]; then
                target="${idx_to_user[$sel]}"
                if [ -n "${idx_to_elapsed[$sel]}" ]; then
                    tmux send-keys -t "${SESSION}:${target}" C-c 2>/dev/null
                    echo "Đã gửi lệnh dừng ghi cho $target, file sẽ được lưu."
                else
                    echo "$target hiện không đang ghi."
                fi
            else
                echo "Số không hợp lệ."
            fi
            pause ;;
        2)
            read -rp "Xác nhận DỪNG TOÀN BỘ? (y/n): " ans
            if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                graceful_stop_session
                echo "Đã dừng toàn bộ (đã lưu các file đang ghi dở trước khi tắt)."
            fi
            pause ;;
        3)
            read -rp "Nhập số user muốn sửa cấu hình: " sel
            if [[ "$sel" =~ ^[0-9]+$ ]] && [ -n "${idx_to_user[$sel]}" ]; then
                edit_user_config "${idx_to_user[$sel]}"
            else
                echo "Số không hợp lệ."
                pause
            fi
            ;;
        0|"") return ;;
        *) echo "Không hợp lệ."; pause ;;
    esac
}

while true; do
    clear
    auto_status="TAT"
    if tmux has-session -t "$SESSION" 2>/dev/null; then auto_status="BAT"; fi
    telegram_cfg=$(get_config TELEGRAM off)
    interval_cfg=$(get_config INTERVAL 5)
    echo "======================================"
    echo "   TIKTOK LIVE RECORDER - MENU"
    echo "======================================"
    echo "1. Ghi thu cong / Dung ghi thu cong"
    echo "2. Cai dat AUTO mac dinh [Auto:$auto_status | Upload:$telegram_cfg | Chu ky:${interval_cfg}p]"
    echo "3. Quan ly danh sach theo doi"
    echo "4. Video (xem / upload Telegram / xoa)"
    echo "5. Trang thai chi tiet + cau hinh rieng tung user"
    echo "0. Thoat"
    echo "======================================"
    read -rp "Chọn: " choice
    case $choice in
        1) record_menu ;;
        2) auto_settings_menu ;;
        3) manage_watchlist ;;
        4) list_and_manage_recordings ;;
        5) show_status_and_control ;;
        0) exit 0 ;;
        *) echo "Lựa chọn không hợp lệ."; pause ;;
    esac
done
