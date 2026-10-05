# VN-MARKET-MCP — Đường ống nghiên cứu giao dịch cổ phiếu Việt Nam

## ⚠️ Tuyên bố từ chối trách nhiệm

Công cụ hỗ trợ **nghiên cứu và ra quyết định**, **KHÔNG PHẢI tư vấn đầu tư** và **KHÔNG** tự động đặt lệnh. Toàn bộ rủi ro giao dịch do nhà đầu tư tự chịu.

---

## 1. Tổng quan dự án

**vn-market-mcp** là một đường ống dữ liệu xác định, viết bằng code, dành cho nghiên cứu các mã cổ phiếu thị trường Việt Nam (ban đầu tập trung vào chỉ số VN30). Hệ thống:

- Lấy dữ liệu thị trường từ **vnstock**
- Chạy kiểm tra chất lượng dữ liệu
- Tính toán các chỉ báo kỹ thuật và cơ bản
- Cho điểm từng mã dựa trên thành phần kỹ thuật, tài chính, dòng tiền ngoại và breadth thị trường
- Gating theo độ phủ dữ liệu (VN30 vs. mã không VN30)
- Tạo nhãn hành động được code quyết định (không phải LLM): `buy_accumulate` / `watch` / `hold` / `reduce_exit` / `stay_out`
- Cung cấp kế hoạch rủi ro dựa trên ATR và lưu ảnh chụp vào PostgreSQL

**Nguyên tắc thiết kế:** Python thực hiện tính toán, bất kỳ LLM nào trong tương lai chỉ giải thích kết quả. Không có vai trò LLM, giao diện chat hay trình lập lịch cron — hiện tại chỉ có đường ống CLI theo yêu cầu.

**Tài liệu thiết kế:** Xem `../vn-trading-agent-plan_final.md`  
**Kế hoạch triển khai:** Xem `../docs/superpowers/plans/2026-09-30-vn-trading-agent-phase-0-1.md`

---

## 2. Nội dung dự án (Phase 0 + Phase 1)

### Phase 0 — Nền tảng

| Thành phần | Mô tả |
|-----------|-------|
| `providers/vnstock_provider.py` | Wrapper vnstock, chuẩn hóa đơn vị VND |
| `pipeline/calendar.py` | Tra cứu lịch giao dịch (fail-closed) |
| `pipeline/ingest.py` | Ingestion OHLCV, cơ bản, dòng tiền idempotent |
| `quality/checks.py` | 6 kiểm tra chất lượng dữ liệu |
| `pipeline/indicators.py` | MA/EMA/RSI/MACD/Bollinger/ATR (pandas) |
| `pipeline/fundamentals.py` | Tỷ số cơ bản theo ngành (P/E, P/B, ROE) |
| `pipeline/scoring.py` | Cho điểm kỹ thuật, tài chính, dòng tiền, breadth |
| `pipeline/action_label.py` | Hàm quyết định nhãn hành động (code-only) |
| `pipeline/risk_plan.py` | Stop-loss dựa ATR, R:R, sizing theo board-band |
| `pipeline/coverage.py` | Giải quyết mã + gating độ phủ non-VN30 |
| `pipeline/theses.py` | Luận điểm đầu tư theo phiên bản |
| `pipeline/positions.py` | Trạng thái "tôi đang nắm giữ cái này" |
| `pipeline/snapshot.py` | Ghi snapshot.json của phiên chạy |
| `pipeline/run_analysis.py` | Orchestrate toàn bộ + entrypoint CLI |
| `db/` | Lược đồ PostgreSQL, migrations, thiết lập role |
| `ops/backup.sh, restore_test.sh` | Backup/restore drill pg_dump |
| `ops/alerting.py` | JSON-line logging + cảnh báo Telegram |
| `mcp_server/` | MCP protocol server (stdio) với 8 công cụ |
| `evals/compare_models.py` | Harness so sánh các mô hình Claude |

### Phase 1 — Cải tiến (2026-10-05)

**Xử lý dữ liệu trong phiên:**
- Worker và job queue nền (`ops/worker.py`, `pipeline/jobs.py`)
- Trình lập lịch cron với các slot intraday (`ops/scheduler.py`): 09:15/11:00/13:00 VN, close_sync 15:05, verdict 15:20, retry 18:00
- Nhãn aware phiên (`provisional_label`): chạy trong phiên chỉ hiển thị/lưu downgrades khi stop bị vi phạm hoặc di chuyển >2 ATR; upgrades chờ closing prices
- `snapshot.session` ghi live_label vs official_label

**Phát hiện giá rebasing:**
- `sync_recent_prices()` phát hiện điều chỉnh dividend/split của vnstock
- So sánh các nến đóng cửa với dữ liệu nhà cung cấp (tolerance 0.1%)
- Nếu phát hiện, tải lại toàn bộ lịch sử từ ngày đầu tiên

**Thành phần cho điểm thực:**
- **Technical trend**: MA20/50/200, MACD, RSI bands
- **Fundamental valuation**: P/E/P/B so với quý trước của chính nó + các peer trong ngành
- **Foreign flow**: Dòng tiền ngoại 5 phiên chuẩn hóa theo giá trị giao dịch (±10% = 100/0 điểm)
- **Market breadth**: VN30 advancers, % trên MA50, liquidity ratio (chỉ tính sau 15:00)

**Dọn dẹp:**
- Xóa `llm/batch.py` (dead code)
- Loại bỏ khóa LLM từ worker (llm.pipeline_enabled: false làm chúng không sử dụng)

**KHÔNG trong giai đoạn này** (theo thiết kế — xem roadmap kế hoạch để giai đoạn sau):
- Giao diện Telegram / chat (chỉ cảnh báo ops lỗi)
- Bất kỳ vai trò LLM nào (tin tức, macro, tổng hợp, Bull/Bear) — bị vô hiệu, giữ để re-enable sau
- Grading dự đoán / forward-test scoring
- Data retention / archival jobs

---

## 3. Yêu cầu

- Python 3.11+
- Docker + Docker Compose (cho PostgreSQL)
- Tài khoản vnstock/API key (Community tier) nếu muốn dữ liệu thị trường thực
- Anthropic API key chỉ nếu chạy `evals/compare_models.py` với dữ liệu thực

---

## 4. Cài đặt

### 4.1 Khởi động PostgreSQL

```bash
docker compose up -d postgres
```

PostgreSQL chạy trên `127.0.0.1:55432` (KHÔNG phải 5432 mặc định — để tránh xung đột với các instance Postgres khác).

### 4.2 Tạo file `.env`

```bash
cp .env.example .env
chmod 600 .env
```

Chỉnh sửa `.env` và đặt giá trị thực cho:
- `MCP_RO_PASSWORD`
- `PIPELINE_RW_PASSWORD`
- `RETENTION_JOB_PASSWORD` (dùng để tạo restricted DB roles)
- `VNSTOCK_API_KEY` / `ANTHROPIC_API_KEY` / `TELEGRAM_BOT_TOKEN` (nếu cần)

`DATABASE_URL` đã trỏ tới PostgreSQL docker-compose trên port 55432 theo mặc định.

### 4.3 Tạo virtualenv và cài đặt dependency

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

### 4.4 Export `.env` vào shell (cần cho mọi lệnh dưới đây)

```bash
export $(cat .env | xargs)
```

### 4.5 Áp dụng database migrations

```bash
.venv/bin/python -c "
from db.connection import get_conn
from db.migrate import apply_migrations
from pathlib import Path
with get_conn() as c:
    print(apply_migrations(c, Path('db/migrations')))
"
```

### 4.6 Tạo các restricted database roles

```bash
.venv/bin/python -m db.setup_roles
```

### 4.7 Seed lịch giao dịch (bắt buộc trước khi chạy analysis)

```bash
.venv/bin/python -c "
from db.connection import get_conn
from pipeline.calendar import seed_calendar_from_weekdays
from datetime import date
with get_conn() as c:
    seed_calendar_from_weekdays(c, date(2020, 1, 1), date(2027, 12, 31), holidays=set())
    c.commit()
"
```

Đây là seed weekday đơn giản không loại trừ các ngày lễ công cộng Việt Nam — đủ cho testing cục bộ. Chạy lại định kỳ (ít nhất một năm một lần) để lịch tiếp tục phủ "hôm nay".

### 4.8 Xác minh lịch đã được seed

```bash
.venv/bin/python -c "
from db.connection import get_conn
from pipeline.calendar import latest_trading_day
from datetime import datetime, timezone
with get_conn() as c:
    latest = latest_trading_day(c, datetime.now(timezone.utc))
    print(f'Latest trading day in calendar: {latest}')
"
```

---

## 5. Sử dụng

### Chạy một phân tích on-demand

```bash
.venv/bin/python -m pipeline.run_analysis VNM --style long --depth quick
```

**Tham số:**
- `ticker`: Mã cổ phiếu (e.g., `VNM`, `FPT`)
- `--style`: `short` (chỉ điểm số) hoặc `long` (bao gồm lý do + warnings)
- `--depth`: `quick` (2 năm dữ liệu) hoặc `full` (toàn bộ lịch sử)

**Output:**
- In JSON report của phiên chạy tới stdout
- Lưu vào file `snapshots/` theo `run_id`
- Lưu vào bảng `snapshots` trong PostgreSQL

### Chạy scheduler nền

```bash
.venv/bin/python -m ops.scheduler
```

Trình lập lịch tự động:
- 08:20 VN mỗi ngày: ingest dữ liệu ngày hôm qua, chạy official verdict cho toàn bộ VN30
- 09:15 / 11:00 / 13:00 VN: chạy phiên chạy provisional (mid-session) cho các mã trong danh sách observe
- 15:05 VN: close_sync (lấy OHLCV + flow cuối phiên)
- 15:20 VN: official verdict cho VN30
- 18:00 VN: retry các job bị lỗi

### Chạy worker

```bash
.venv/bin/python -m ops.worker
```

Xử lý các job từ hàng đợi. Chạy nhiều worker instances để xử lý song song.

### Xem tool MCP

```bash
.venv/bin/python -m mcp_server.server
```

Bắt đầu MCP server (stdio). Các client MCP (e.g., Hermes) có thể gọi 8 tool được expose.

---

## 6. Cấu hình

### File `vn-rules.yaml`

Lưu trữ các config:
- `trading_hours`: Định nghĩa giờ giao dịch (morning/afternoon)
- `snapshot_cache.max_age_minutes`: TTL cache cho on-demand runs
- `llm.pipeline_enabled`: Enable/disable LLM roles (hiện tại `false`)

### File `config.yaml`

Cấu hình ứng dụng:
- `database_url`: Chuỗi kết nối PostgreSQL
- `log_level`: Mức logging
- `telegram_bot_token`, `telegram_ops_group_id`: Cảnh báo Telegram

---

## 7. Cấu trúc Database

### Bảng chính

| Bảng | Mục đích |
|------|---------|
| `trading_calendar` | Các ngày giao dịch + flags |
| `prices_daily` | OHLCV hàng ngày + source |
| `price_adjustments` | Điều chỉnh dividend/split |
| `foreign_flow_daily` | Dòng tiền ngoại |
| `fundamentals_quarterly` | P/E, P/B, ROE, v.v. theo quý |
| `news_items` | Tiêu đề tin tức (thô, không LLM) |
| `corporate_events` | Sự kiện: dividend, split, ESOP |
| `snapshots` | Ảnh chụp phiên chạy (JSONB) |
| `report_commentary` | Nhận định AI + fingerprint |
| `jobs` | Hàng đợi job + status |
| `market_regime_daily` | VN30 advancers, breadth metrics |

---

## 8. CI/CD & Testing

### Chạy test suite

```bash
.venv/bin/pytest tests/ -v
```

Mục tiêu: ≥95% độ bao phủ cho logic quyết định (action_label, scoring, calendar).

### GitHub Actions

`.github/workflows/` gồm:
- `test.yml`: Chạy pytest + coverage
- `lint.yml`: Black, isort, pyright type check
- Chưa có: deployment workflow (Phase 2)

---

## 9. Architecture & Design

### Data Flow

```
vnstock API
    ↓
ingest.py (OHLCV, fundamentals, flow, news)
    ↓
PostgreSQL (upsert idempotent)
    ↓
Quality checks (6 validations)
    ↓
Indicators (MA, RSI, MACD, ATR)
    ↓
Scoring (technical, fundamental, flow, breadth)
    ↓
Action label (deterministic decision)
    ↓
Risk plan (ATR-based stop/R:R)
    ↓
Snapshot (JSON → postgres + file)
```

### Session-aware Label Logic

**Trong phiên (09:15 - 15:00 VN):**
- Nến là ảnh chụp trực tiếp, chưa kóa
- Chỉ downgrade nhãn nếu rủi ro được kích hoạt (stop bị vi phạm hoặc di chuyển >2 ATR)
- KHÔNG upgrade trước khi đóng cửa (chờ closing prices)
- Cap "buy" ở "watch" nếu không có official label

**Sau phiên (15:05+):**
- OHLCV là dữ liệu kóa
- close_sync lấy final bars + phát hiện rebasing
- official verdict được tính từ dữ liệu cuối phiên
- Nhãn được lưu trong `snapshot.session.official_label`

---

## 10. Xử lý sự cố

### Lỗi `data_quality_error: missing_tickers`

**Nguyên nhân:** Chạy trước 09:15 VN, không có nến cho hôm nay, completeness check thất bại.

**Fix:** `latest_trading_day()` bây giờ kiểm tra VN timezone, trả về phiên trước trước 09:15.

### Giá bị "kẹt" ở giữa phiên

**Nguyên nhân:** Nến mid-session được lưu, never được thay thế bằng closing bar.

**Fix:** `close_sync` chạy lúc 15:05, tái ingestion 10 ngày gần đây + phát hiện rebasing.

### Nhãn chuyển từ `buy` → `watch` giữa phiên

**Nguyên nhân:** Sự cố; downgrades được dự kiến.

**Fix:** Kiểm tra `snapshot.session.live_label` vs `official_label` trong report.

### PostgreSQL connection timeout

```bash
# Kiểm tra connection
psql -h 127.0.0.1 -p 55432 -U postgres -d vn_market -c "SELECT 1"

# Rebuild container
docker compose down && docker compose up -d postgres
```

---

## 11. Công cụ MCP

Các công cụ được expose qua MCP protocol (stdio):

1. **run_analysis_tool** — Enqueue on-demand analysis
2. **get_job_status_tool** — Poll job status
3. **get_snapshot_tool** — Lấy snapshot kết quả
4. **get_stock_report_tool** — Render stock report (code + cached commentary)
5. **save_commentary_tool** — Lưu AI commentary + verify
6. **list_snapshots_tool** — Liệt kê snapshots
7. **get_market_regime_tool** — VN30 breadth + regime
8. **get_position_tool** — Trạng thái portfolio

Sử dụng từ Hermes hoặc bất kỳ MCP client nào khác.

---

## 12. Giới hạn & Hạn chế đã biết

- **Non-VN30 tickers:** Có thể thiếu dữ liệu cơ bản → bị gate nếu <3 quý
- **Foreign flow:** Chỉ Hiệp hội nhà cung cấp liquidity (KBS); không bao gồm flow cá nhân
- **News:** Best-effort; flaky API không làm phiên chạy fail, chỉ bỏ qua news
- **LLM roles:** Hiện bị vô hiệu; re-enable via `llm.pipeline_enabled: true` (Phase 2)
- **Calendar:** Cần re-seed hàng năm để phủ các năm mới
- **Timezone:** Luôn luôn VN (Asia/Ho_Chi_Minh); không hỗ trợ timezone khác

---

## 13. Phát triển

### Thêm một mã mới

```python
from pipeline.run_analysis import run_analysis
result = run_analysis("XXX", style="long", depth="quick")
print(result["action_label"], result["composite_score"])
```

### Mở rộng chỉ báo

Thêm vào `pipeline/indicators.py`, expose trong `pipeline/scoring.py`.

### Thêm LLM role

Đặt `llm.pipeline_enabled: true` trong `vn-rules.yaml`, define role trong `llm/roles/`.

---

## 14. Liên hệ & Đóng góp

- **Issues:** GitHub Issues
- **Discussion:** GitHub Discussions
- **Ops Alert:** Telegram (cảnh báo tự động khi job fail)

---

## 15. Giấy phép

Xem LICENSE file.

---

**Lần cập nhật cuối cùng:** 2026-10-05  
**Phase:** 1 (basic pipeline + session-aware labels + real scoring)
