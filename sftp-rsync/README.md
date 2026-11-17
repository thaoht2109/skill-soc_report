# sftp-sync

Kéo dữ liệu một chiều từ SFTP server về máy, đăng nhập bằng tài khoản + mật khẩu qua cổng 22.
Chỉ tải file mới hoặc đã thay đổi. Không xóa gì ở nguồn lẫn ở đích: file bị xóa trên server vẫn được giữ lại ở máy này.

Script tự chọn cách chạy:

- Server cho SSH shell và có `rsync` → dùng `rsync`.
- Server chỉ mở SFTP → dùng `lftp mirror`.

## Cài đặt

```bash
sudo apt install lftp sshpass rsync
cp .env.example .env && chmod 600 .env   # rồi điền thông tin
```

## Nhiều thư mục

Mặc định đồng bộ một cặp `REMOTE_DIR` → `LOCAL_DIR`. Muốn nhiều thư mục (cùng server, cùng tài khoản) thì khai `SYNC_DIRS` trong `.env`, mỗi cặp một dòng `"nguồn|đích"`:

```bash
SYNC_DIRS=(
  "/data|/srv/backup/data"
  "/logs|/srv/backup/logs"
)
```

Các cặp chạy lần lượt. Một cặp lỗi không chặn các cặp sau; script vẫn thoát khác 0 để báo có lỗi. Khi có `SYNC_DIRS` thì `REMOTE_DIR`/`LOCAL_DIR` bị bỏ qua.

## Chạy

```bash
./sftp-sync.sh -n            # chạy thử, chỉ liệt kê, không tải
./sftp-sync.sh               # đồng bộ thật
./sftp-sync.sh -c /etc/sftp-sync/khac.env   # dùng file cấu hình khác
```

Mã thoát khác 0 khi lỗi. Sai mật khẩu thì dừng ngay, không thử lại.

Lần kết nối đầu, host key của server được ghi vào `~/.ssh/known_hosts`. Nếu sau này key đổi, script từ chối kết nối cho tới khi bạn tự xử lý (`ssh-keygen -R <host>`).

## Khi bị gián đoạn giữa chừng

Mất mạng hay server lỗi lúc đang tải thì lượt chạy đó thoát với mã lỗi, file đang tải nằm dở ở đích. Lượt chạy kế (service tự chạy lại) so kích thước với nguồn, thấy file chưa đủ và tải tiếp phần còn thiếu. File đã tải xong không bị tải lại.

Lưu ý: trong khoảng giữa hai lượt, file tải dở vẫn nằm ở đích dưới tên thật với nội dung chưa đủ. Chương trình khác đọc thư mục đích nên tính tới điều này.

## Chạy dạng service (systemd)

Service tự chạy khi máy khởi động, mỗi lượt xong thì chờ rồi chạy lượt kế, lỗi cũng tự chạy lại.

```bash
sudo ./install-service.sh            # cài, 300 giây giữa hai lượt
sudo ./install-service.sh -i 60      # đổi chu kỳ thành 60 giây (chạy lại lệnh để cập nhật)
./install-service.sh -p              # chỉ xem unit sẽ được ghi
sudo ./install-service.sh -u         # gỡ

systemctl status sftp-sync           # trạng thái
journalctl -u sftp-sync -f           # log
```

- Service chạy bằng user đã gọi `sudo`, dùng `.env` cạnh script. Đừng di chuyển thư mục sau khi cài; nếu chuyển thì cài lại.
- Giữa hai lượt, trạng thái hiện `activating (auto-restart)`: đó là bình thường.
- Sai mật khẩu thì service dừng hẳn (không thử lại, tránh khóa tài khoản). Sửa `.env` rồi chạy `sudo systemctl restart sftp-sync`.

### Nhiều server nguồn (khác IP / tài khoản)

Mỗi server nguồn một file cấu hình riêng, khai `SFTP_HOST` (IP), `SFTP_USER`, `SFTP_PASS`, thư mục của server đó. Cài mỗi file thành một service riêng bằng `-c`; các service chạy song song, không ảnh hưởng nhau.

```bash
cp .env.example may-a.env && chmod 600 may-a.env   # SFTP_HOST=<IP máy A> ...
./sftp-sync.sh -c may-a.env -n                     # chạy thử
sudo ./install-service.sh -c may-a.env -i 30       # service tên sftp-sync-may-a
journalctl -u sftp-sync-may-a -f
sudo ./install-service.sh -c may-a.env -u          # gỡ
```

Tên service lấy từ tên file: bỏ đuôi `.env`, ký tự khác chữ/số/`-`/`_` đổi thành `-` (vd. `ktm.1.env` → `sftp-sync-ktm-1`); installer in tên service khi cài xong. Service `sftp-sync` cũ (dùng `.env`) giữ nguyên.

Server nguồn là máy Linux có cài `rsync` thì script tự dùng rsync; máy đó cần bật đăng nhập SSH bằng mật khẩu (`PasswordAuthentication yes`). Không file nào ở nguồn bị xóa hay sửa.

### Gom nhiều server về chung một thư mục (vd. `Report_ALL`)

**Mỗi server lưu vào một thư mục con riêng** dưới thư mục chung. Không cho nhiều server cùng ghi thẳng vào một thư mục: hai server có file trùng tên sẽ đè nhau mỗi lượt (rsync), hoặc bị nối nội dung thành file hỏng (lftp `--continue` coi file đó là file tải dở).

Ví dụ: kéo `Report_KTM_1` trên máy A và báo cáo từ 5 server khác, tất cả về `/data/Report_ALL` trên máy này:

```
/data/Report_ALL/
├── KTM_1/   <- máy A   10.0.0.11:/home/user/Report_KTM_1
├── KTM_2/   <- server 2 10.0.0.12:/data/report
├── KTM_3/   <- server 3 ...
└── ...
```

Mỗi server một file cấu hình, chỉ khác host, tài khoản, `REMOTE_DIR` và tên thư mục con trong `LOCAL_DIR`:

```bash
# ktm1.env
SFTP_HOST=10.0.0.11
SFTP_USER=tai_khoan
SFTP_PASS='mat_khau'
REMOTE_DIR=/home/user/Report_KTM_1
LOCAL_DIR=/data/Report_ALL/KTM_1

# ktm2.env
SFTP_HOST=10.0.0.12
SFTP_USER=tai_khoan_2
SFTP_PASS='mat_khau_2'
REMOTE_DIR=/data/report
LOCAL_DIR=/data/Report_ALL/KTM_2
```

Cài và chạy:

```bash
chmod 600 ktm*.env
for f in ktm*.env; do ./sftp-sync.sh -c "$f" -n; done                 # chạy thử từng server
for f in ktm*.env; do sudo ./install-service.sh -c "$f" -i 300; done  # mỗi server một service, chạy song song
systemctl list-units 'sftp-sync-*'                                    # xem trạng thái tất cả
journalctl -u sftp-sync-ktm2 -f                                       # log một server
```

- Script chép **nội dung** của `REMOTE_DIR` (file + mọi thư mục con) vào đúng `LOCAL_DIR`. Muốn giữ cả tên thư mục gốc thì đặt nó ở cuối `LOCAL_DIR`: `REMOTE_DIR=/home/ai/Report_KTM_1` + `LOCAL_DIR=/data/Report_ALL/Report_KTM_1`.
- Thư mục con tự được tạo ở lượt chạy đầu, không cần tạo trước.
- Một server lỗi (mất mạng, sai mật khẩu) chỉ dừng service của server đó; các server khác vẫn chạy.
- Thêm server sau này: tạo thêm `ktmN.env` với `LOCAL_DIR=/data/Report_ALL/KTM_N` rồi cài như trên.
- Server cần lấy nhiều thư mục: dùng `SYNC_DIRS` trong file của server đó, mọi đích vẫn nằm dưới thư mục con của nó, vd. `"/data/report|/data/Report_ALL/KTM_2/report"`.

## Cron (thay cho service)

```cron
*/30 * * * * /duong/dan/sftp-sync.sh >> /var/log/sftp-sync.log 2>&1
```

Hai lần chạy cùng một file cấu hình không chồng nhau (lần sau thoát ngay nếu lần trước chưa xong).
