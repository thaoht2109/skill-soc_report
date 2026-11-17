#!/usr/bin/env bash
# Kiểm thử đầu-cuối bằng Docker: server sftp-only (nhánh lftp) và server có shell + rsync (nhánh rsync).
# Kiểm: tải đủ file, chạy lại không lỗi, xóa ở nguồn không làm mất ở đích, nguồn không bị đụng, sai mật khẩu thì lỗi.
set -euo pipefail
cd "$(dirname "$0")"
P=sftpsync-test-$$
trap 'docker rm -f $P-sftp $P-ssh $P-cli >/dev/null 2>&1; docker network rm $P >/dev/null 2>&1' EXIT

docker network create $P >/dev/null
docker run -d --name $P-sftp --network $P --ulimit nofile=65535 atmoz/sftp u:secret:::data >/dev/null
docker run -d --name $P-ssh --network $P --ulimit nofile=65535 alpine sh -c '
  apk add -q openssh-server rsync && ssh-keygen -A >/dev/null && adduser -D u && echo u:secret | chpasswd &&
  mkdir -p /data && chown u /data && exec /usr/sbin/sshd -D -e' >/dev/null
docker run -d --name $P-cli --network $P -v "$PWD/sftp-sync.sh:/sftp-sync.sh:ro" alpine sleep 600 >/dev/null
docker exec $P-cli apk add -q bash lftp sshpass rsync openssh-client coreutils util-linux

cli() { docker exec $P-cli bash -c "$1"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# $1=container server, $2=thư mục dữ liệu thật trên server, $3=mode mong đợi
check() {
  local srv=$1 dir=$2 mode=$3 out
  echo "== $srv (mong đợi mode=$mode)"
  for _ in $(seq 30); do cli "nc -z $srv 22" 2>/dev/null && break; sleep 1; done
  docker exec "$srv" sh -c "mkdir -p $dir/sub && echo a > $dir/a.txt && head -c 300000 /dev/urandom > $dir/big.bin && touch -d @1700000000 $dir/big.bin && echo b > '$dir/sub/b c.txt' && mkdir -p '$dir/thu muc' && echo t > '$dir/thu muc/t.txt' && chmod -R a+rX $dir"
  cli "printf 'SFTP_HOST=$srv\nSFTP_USER=u\nSFTP_PASS=secret\nREMOTE_DIR=/data\nLOCAL_DIR=/dst-$mode/\n' > /$mode.env; chmod 600 /$mode.env"

  cli "/sftp-sync.sh -n -c /$mode.env" >/dev/null
  cli "[ ! -e /dst-$mode/a.txt ]" || fail "dry-run đã tải file"

  out=$(cli "/sftp-sync.sh -c /$mode.env")
  [[ $out == *"mode=$mode"* ]] || fail "sai mode: $out"
  cli "[ \"\$(cat /dst-$mode/a.txt)\" = a ] && [ \"\$(cat '/dst-$mode/sub/b c.txt')\" = b ]" || fail "thiếu file sau lần đầu"

  # Giả lập bị ngắt giữa chừng: file ở đích bị cụt và có mtime mới. Lượt sau phải tải cho đủ.
  cli "head -c 1000 /dst-$mode/big.bin > /tmp/p && mv /tmp/p /dst-$mode/big.bin"
  docker exec "$srv" sh -c "rm $dir/a.txt && echo c > $dir/c.txt"
  cli "/sftp-sync.sh -c /$mode.env" >/dev/null
  [[ $(cli "sha256sum < /dst-$mode/big.bin") == "$(docker exec "$srv" sh -c "sha256sum < $dir/big.bin")" ]] || fail "file tải dở không được tải lại cho đủ"
  cli "[ -f /dst-$mode/a.txt ] && [ -f /dst-$mode/c.txt ]" || fail "file đã xóa ở nguồn bị mất ở đích, hoặc thiếu file mới"
  docker exec "$srv" sh -c "[ -f '$dir/sub/b c.txt' ] && [ -f $dir/c.txt ]" || fail "nguồn bị thay đổi"

  # Nhiều thư mục: cặp lỗi (nguồn không tồn tại) không chặn các cặp sau, nhưng mã thoát phải khác 0.
  docker exec -i $P-cli sh -c "cat > /multi-$mode.env && chmod 600 /multi-$mode.env" <<EOF
SFTP_HOST=$srv
SFTP_USER=u
SFTP_PASS=secret
SYNC_DIRS=(
  "/data/khong-co|/m-$mode/x"
  "/data/sub|/m-$mode/s"
  "/data/thu muc|/m-$mode/t"
  "/data|/m-$mode/d/"
)
EOF
  cli "! /sftp-sync.sh -c /multi-$mode.env >/dev/null 2>&1" || fail "có cặp lỗi mà vẫn thoát 0"
  cli "[ -f '/m-$mode/s/b c.txt' ] && [ -f /m-$mode/d/c.txt ] && [ -f /m-$mode/t/t.txt ]" || fail "nhiều thư mục: thiếu file ở các cặp sau cặp lỗi"

  cli "sed -i 's/secret/wrong/' /$mode.env; /sftp-sync.sh -c /$mode.env 2>/dev/null; [ \$? -eq 77 ]" || fail "sai mật khẩu phải thoát mã 77"
  echo "   OK"
}

check $P-sftp /home/u/data lftp
check $P-ssh /data rsync
echo "TẤT CẢ ĐẠT"
