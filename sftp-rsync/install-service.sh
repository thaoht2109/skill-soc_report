#!/usr/bin/env bash
# Cài sftp-sync thành service systemd: tự chạy khi khởi động, lặp lại sau mỗi chu kỳ, tự chạy lại khi lỗi.
# Dùng: sudo ./install-service.sh [-c file.env] [-i giây]   cài/cập nhật (mặc định 300 giây giữa hai lượt)
#            ./install-service.sh [-c file.env] -p [-i giây] chỉ in unit ra màn hình
#       sudo ./install-service.sh [-c file.env] -u           gỡ service
# Không có -c: dùng .env cạnh script, service tên sftp-sync.
# -c ten.env: service riêng tên sftp-sync-ten (mỗi server nguồn một file cấu hình, chạy song song được).
set -euo pipefail

DIR=$(dirname "$(readlink -f "$0")")
ENVF=$DIR/.env
NAME=sftp-sync
RUN_AS=${SUDO_USER:-$(id -un)}
INTERVAL=300
ACTION=install
while getopts "c:i:pu" opt; do
  case $opt in
    c) ENVF=$(readlink -f "$OPTARG")
       # Tên service lấy từ tên file: bỏ đuôi .env và dấu chấm đầu, ký tự khác chữ/số/-/_ đổi thành "-".
       base=$(basename "$ENVF" .env)
       base=${base#.}
       base=${base//[^A-Za-z0-9_-]/-}
       NAME=sftp-sync-$base ;;
    i) INTERVAL=$OPTARG ;;
    p) ACTION=print ;;
    u) ACTION=uninstall ;;
    *) echo "Dùng: $0 [-c file.env] [-i giây] [-p] [-u]" >&2; exit 1 ;;
  esac
done
[[ $INTERVAL =~ ^[0-9]+$ ]] || { echo "LỖI: -i phải là số giây" >&2; exit 1; }
UNIT=/etc/systemd/system/$NAME.service

unit() {
  cat <<EOF
[Unit]
Description=Dong bo du lieu tu SFTP server ($NAME)
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$RUN_AS
ExecStart="$DIR/sftp-sync.sh" -c "$ENVF"
# Mỗi lượt xong (thành công hay lỗi) thì chờ rồi chạy lượt kế; không bao giờ chồng lượt.
Restart=always
RestartSec=$INTERVAL
# 77 = sai mật khẩu: dừng hẳn để không làm khóa tài khoản trên server.
RestartPreventExitStatus=77
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF
}

case $ACTION in
  print) unit ;;
  uninstall)
    systemctl disable --now "$NAME.service" || true
    rm -f "$UNIT"
    systemctl daemon-reload
    echo "Đã gỡ service $NAME." ;;
  install)
    (( EUID == 0 )) || { echo "LỖI: cần quyền root: sudo $0" >&2; exit 1; }
    [[ -f $ENVF ]] || { echo "LỖI: chưa có $ENVF (xem .env.example)" >&2; exit 1; }
    command -v lftp >/dev/null && command -v sshpass >/dev/null ||
      { echo "LỖI: cần cài cả hai gói: apt install lftp sshpass" >&2; exit 1; }
    unit > "$UNIT"
    systemctl daemon-reload
    systemctl enable "$NAME.service"
    systemctl restart "$NAME.service"
    echo "Đã cài $NAME: chạy bằng user $RUN_AS, $INTERVAL giây giữa hai lượt, cấu hình $ENVF."
    echo "Trạng thái: systemctl status $NAME    Log: journalctl -u $NAME -f" ;;
esac
