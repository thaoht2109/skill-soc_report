#!/usr/bin/env bash
# Kéo dữ liệu từ SFTP server về thư mục local (một chiều, không xóa gì ở cả hai phía).
# Server có shell + rsync -> dùng rsync; còn lại -> lftp mirror qua giao thức SFTP.
# Dùng: sftp-sync.sh [-c file.env] [-n]      (-n: chạy thử, không tải)
set -euo pipefail

die() { echo "LỖI: $*" >&2; exit 1; }
log() { echo "[$(date '+%F %T')] $*"; }

ENV_FILE="$(dirname "$(readlink -f "$0")")/.env"
DRY=0
while getopts "c:n" opt; do
  case $opt in
    c) ENV_FILE=$OPTARG ;;
    n) DRY=1 ;;
    *) die "Dùng: $0 [-c file.env] [-n]" ;;
  esac
done

[[ -f $ENV_FILE ]] || die "không thấy file cấu hình $ENV_FILE (xem .env.example)"
(( 0$(stat -c %a "$ENV_FILE") & 077 )) && die "$ENV_FILE chứa mật khẩu, hãy chạy: chmod 600 $ENV_FILE"
# shellcheck disable=SC1090
. "$ENV_FILE"
SFTP_PORT=${SFTP_PORT:-22}
for v in SFTP_HOST SFTP_USER SFTP_PASS; do
  [[ -n ${!v:-} ]] || die "thiếu biến $v trong $ENV_FILE"
done
# Danh sách cặp "nguồn|đích". Không khai SYNC_DIRS thì dùng một cặp REMOTE_DIR/LOCAL_DIR.
if [[ -z ${SYNC_DIRS+x} ]]; then
  [[ -n ${REMOTE_DIR:-} && -n ${LOCAL_DIR:-} ]] || die "cần SYNC_DIRS hoặc REMOTE_DIR + LOCAL_DIR trong $ENV_FILE"
  SYNC_DIRS=("$REMOTE_DIR|$LOCAL_DIR")
fi
for p in "${SYNC_DIRS[@]}"; do
  [[ $p == ?*"|"?* ]] || die "SYNC_DIRS: mục '$p' phải có dạng 'thư_mục_nguồn|thư_mục_đích'"
done

# Khóa theo file cấu hình: hai lần chạy cron không chồng nhau.
exec 9<"$ENV_FILE"
flock -n 9 || die "một tiến trình đồng bộ khác đang chạy với $ENV_FILE"

# accept-new: ghi nhận host key lần đầu, từ chối nếu key bị đổi.
# keyboard-interactive: nhiều server (PAM) hỏi mật khẩu qua kiểu này chứ không phải "password".
# ServerAlive*: đường truyền chết lặng (không RST) thì ssh tự thoát sau ~60 giây thay vì treo vô hạn.
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4"

# Dò xem server có cho chạy rsync không. So nội dung trả về chứ không tin mã thoát:
# server sftp-only có thể trả 0 dù không chạy lệnh nào.
# stdout phải BẮT ĐẦU bằng "rsync ... version": nếu shell trên server in thêm chữ (.bashrc có echo)
# thì giao thức rsync sẽ hỏng, khi đó dùng lftp. stderr (banner, cảnh báo của ssh) tách riêng.
mode=lftp
if command -v sshpass >/dev/null; then
  err=$(mktemp)
  trap 'rm -f "$err"' EXIT
  rc=0
  # shellcheck disable=SC2086
  out=$(SSHPASS=$SFTP_PASS timeout 30 sshpass -e ssh -n $SSH_OPTS -p "$SFTP_PORT" \
        "$SFTP_USER@$SFTP_HOST" 'rsync --version' 2>"$err") || rc=$?
  errtxt=$(<"$err")
  # Sai mật khẩu: dừng ngay, không thử lại bằng lftp (tránh khóa tài khoản).
  # Mã 77 để systemd (RestartPreventExitStatus) không tự chạy lại.
  # Chỉ khớp thông báo xác thực của ssh ("user@host: Permission denied (password)."),
  # không khớp "Permission denied" do lệnh phía server in ra.
  if (( rc == 5 )) || [[ $errtxt == *": Permission denied ("* || $errtxt == *"Too many authentication failures"* ]]; then
    echo "LỖI: đăng nhập $SFTP_USER@$SFTP_HOST:$SFTP_PORT thất bại: $errtxt" >&2
    exit 77
  fi
  if [[ $out == "rsync "*version* ]]; then
    mode=rsync
  else
    log "Không dùng được rsync qua SSH (mã $rc${errtxt:+: ${errtxt##*$'\n'}}), chuyển sang lftp."
  fi
fi

[[ $mode == rsync ]] || command -v lftp >/dev/null ||
  die "cần lftp (server không chạy được rsync): sudo apt install lftp sshpass"

# Đồng bộ một cặp: $1 = thư mục nguồn trên server, $2 = thư mục đích trên máy này.
sync_one() {
  local remote=$1 local_dir=${2%/}   # lftp: đích có "/" cuối sẽ tạo thêm thư mục con
  mkdir -p "$local_dir" || return 1
  log "[$mode] $SFTP_USER@$SFTP_HOST:$remote -> $local_dir"
  if [[ $mode == rsync ]]; then
    # -s: đường dẫn nguồn có khoảng trắng/ký tự đặc biệt không bị shell phía server tách ra.
    # --timeout: không có dữ liệu qua lại 120 giây thì thoát lỗi thay vì treo.
    local rc=0 args=(-av -s --partial --timeout=120)
    (( DRY )) && args+=(-n)
    # Không --delete, không --remove-source-files.
    SSHPASS=$SFTP_PASS sshpass -e rsync "${args[@]}" -e "ssh $SSH_OPTS -p $SFTP_PORT" \
      "$SFTP_USER@$SFTP_HOST:${remote%/}/" "$local_dir/" || rc=$?
    # 24 = file biến mất ở nguồn giữa lúc liệt kê và lúc tải (nguồn đang hoạt động): không phải lỗi.
    if (( rc == 24 )); then
      log "Cảnh báo: một số file ở nguồn biến mất trong lúc đồng bộ, bỏ qua."
      rc=0
    fi
    return $rc
  else
    local dry=""
    (( DRY )) && dry="--dry-run"
    # Không --delete, không --Remove-source-files.
    # Không --only-newer: file tải dở có mtime mới hơn nguồn nên sẽ bị bỏ qua mãi mãi.
    # --continue: file tải dở (nhỏ hơn nguồn) được tải tiếp ở lượt sau.
    # ponytail: đường dẫn/tên user chứa dấu " sẽ làm hỏng lệnh lftp; cần thì thêm escape.
    LFTP_PASSWORD=$SFTP_PASS lftp -c "
      set cmd:fail-exit yes
      set net:max-retries 3
      set net:timeout 30
      set sftp:connect-program \"ssh -a -x $SSH_OPTS\"
      open --env-password -u \"$SFTP_USER\" -p $SFTP_PORT sftp://$SFTP_HOST
      mirror --continue --verbose $dry \"$remote\" \"$local_dir\"
    "
  fi
}

# Một cặp lỗi không chặn các cặp còn lại; cuối cùng vẫn thoát khác 0 nếu có cặp lỗi.
failed=0
for p in "${SYNC_DIRS[@]}"; do
  rc=0
  sync_one "${p%%|*}" "${p#*|}" || rc=$?
  if (( rc )); then
    echo "LỖI: đồng bộ '${p%%|*}' thất bại (mode=$mode, mã thoát $rc)" >&2
    failed=$((failed + 1))
  fi
done

(( failed == 0 )) || die "$failed/${#SYNC_DIRS[@]} thư mục đồng bộ thất bại (mode=$mode)"
log "Xong ${#SYNC_DIRS[@]} thư mục (mode=$mode)."
