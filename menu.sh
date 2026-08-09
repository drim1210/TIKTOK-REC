#!/bin/bash
cd "$(dirname "$0")" || exit 1
WATCHLIST="watchlist.txt"
SESSION="tiktok"
touch "$WATCHLIST"

pause() { echo ""; read -rp "Bấm Enter để quay lại menu..." _; }

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
                if [ -z "$uname" ]; then echo "Bỏ trống, không thêm."
                elif grep -qxF "$uname" "$WATCHLIST"; then echo "Đã có trong danh sách rồi."
                else echo "$uname" >> "$WATCHLIST"; echo "Đã thêm: $uname"
                fi
                pause ;;
            2)
                if [ ! -s "$WATCHLIST" ]; then echo "Danh sách trống."; pause; continue; fi
                nl -w2 -s". " "$WATCHLIST"
                read -rp "Nhập số dòng muốn xóa: " num
                if [[ "$num" =~ ^[0-9]+$ ]]; then
                    sed -i "${num}d" "$WATCHLIST"
                    echo "Đã xóa dòng $num."
                else
                    echo "Số không hợp lệ."
                fi
                pause ;;
            0) return ;;
            *) echo "Không hợp lệ."; pause ;;
        esac
    done
}
record_watchlist_background() {
    if [ ! -s "$WATCHLIST" ]; then
        echo "Danh sách theo dõi đang trống. Vào mục 'Quản lý danh sách' để thêm username trước."
        pause
        return
    fi
    if ! command -v tmux &> /dev/null; then
        echo "tmux chưa được cài. Cài bằng: sudo apt install tmux -y"
        pause
        return
    fi
    read -rp "Bật upload Telegram? (y/n): " tg
    TG_FLAG=""
    if [ "$tg" = "y" ] || [ "$tg" = "Y" ]; then TG_FLAG="-telegram"; fi
    read -rp "Chu kỳ kiểm tra live (phút, mặc định 5): " interval
    interval=${interval:-5}
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        read -rp "Session '$SESSION' đang chạy rồi. Xóa và khởi động lại theo danh sách mới? (y/n): " ans
        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
            tmux kill-session -t "$SESSION"
        else
            echo "Đã hủy."; pause; return
        fi
    fi
    first=true
    count=0
    while IFS= read -r uname; do
        [ -z "$uname" ] && continue
        CMD="uv run python src/main.py -user $uname -mode automatic -output ~/recordings $TG_FLAG -automatic_interval $interval -no-update-check"
        if $first; then
            tmux new -d -s "$SESSION" -n "$uname" "cd $(pwd) && $CMD"
            first=false
        else
            tmux new-window -t "$SESSION" -n "$uname" "cd $(pwd) && $CMD"
        fi
        count=$((count+1))
    done < "$WATCHLIST"
    echo ""
    echo "Đã bật auto-ghi cho $count user, chạy nền trong tmux session '$SESSION'."
    echo "Giờ có thể tắt điện thoại/Termux thoải mái, VPS vẫn tự ghi."
    echo "Xem lại: tmux attach -t $SESSION"
    echo "(Ctrl+B rồi số cửa sổ để đổi user xem, Ctrl+B D để thoát mà không dừng)"
    pause
}
record_one_user_now() {
    read -rp "Nhập username TikTok (không @): " uname
    if [ -z "$uname" ]; then echo "Username không được để trống."; pause; return; fi
    read -rp "Bật upload Telegram? (y/n): " tg
    TG_FLAG=""
    if [ "$tg" = "y" ] || [ "$tg" = "Y" ]; then TG_FLAG="-telegram"; fi
    echo ""; echo "Đang chạy (foreground, giữ SSH mở)... (Ctrl+C để dừng)"; echo ""
    uv run python src/main.py -user "$uname" -output ~/recordings $TG_FLAG -no-update-check
    pause
}
list_recordings() {
    echo ""; echo "--- Video trong ~/recordings ---"
    ls -lht ~/recordings 2>/dev/null
    echo ""; du -sh ~/recordings 2>/dev/null
    pause
}
delete_recordings() {
    echo ""
    read -rp "XÓA TOÀN BỘ video? Gõ 'yes' để xác nhận: " confirm
    if [ "$confirm" = "yes" ]; then rm -rf ~/recordings/*; echo "Đã xóa xong."; else echo "Đã hủy."; fi
    pause
}
check_running() {
    echo ""; echo "--- Tiến trình đang chạy ---"
    pgrep -af 'src/main.py'
    if [ $? -ne 0 ]; then echo "Không có tiến trình nào đang chạy."; fi
    echo ""
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "--- Cửa sổ tmux đang chạy trong session '$SESSION' ---"
        tmux list-windows -t "$SESSION"
    fi
    pause
}
stop_running() {
    echo ""
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        read -rp "Dừng toàn bộ session tmux '$SESSION'? (y/n): " ans
        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
            tmux kill-session -t "$SESSION"
            echo "Đã dừng session tmux."
        fi
    fi
    pids=$(pgrep -f 'src/main.py')
    if [ -n "$pids" ]; then
        echo "Đang dừng tiến trình còn lại: $pids"
        kill $pids
        sleep 2
        if pgrep -f 'src/main.py' > /dev/null; then kill -9 $pids; fi
        echo "Đã dừng."
    else
        echo "Không còn tiến trình nào chạy ngoài tmux."
    fi
    pause
}
while true; do
    clear
    echo "======================================"
    echo "   TIKTOK LIVE RECORDER - MENU"
    echo "======================================"
    echo "1. Ghi live 1 user NGAY (foreground, test nhanh)"
    echo "2. Bật AUTO-GHI danh sách theo dõi (chạy NỀN, tắt máy vẫn ghi)"
    echo "3. Quản lý danh sách theo dõi (xem/thêm/xóa)"
    echo "4. Xem danh sách video đã ghi"
    echo "5. Xóa toàn bộ video"
    echo "6. Kiểm tra tiến trình đang chạy"
    echo "7. Dừng toàn bộ tiến trình"
    echo "0. Thoát"
    echo "======================================"
    read -rp "Chọn: " choice
    case $choice in
        1) record_one_user_now ;;
        2) record_watchlist_background ;;
        3) manage_watchlist ;;
        4) list_recordings ;;
        5) delete_recordings ;;
        6) check_running ;;
        7) stop_running ;;
        0) exit 0 ;;
        *) echo "Lựa chọn không hợp lệ."; pause ;;
    esac
done
