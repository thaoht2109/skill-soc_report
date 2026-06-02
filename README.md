# Security Report Agent — SOC Report Generator

Custom agent + skill + instruction cho **GitHub Copilot** (VS Code). Tự động sinh báo cáo phân tích bảo mật dạng SOC từ dữ liệu thô (scan, log, incident CSV).

---

## Cấu trúc

```
.github/
├── agents/soc-report.agent.md            # Agent — chuyên gia SOC Tier-2/3
├── instructions/
│   └── report-data-consistency.instructions.md  # Instruction — validation đầu vào
.agents/skills/
└── soc-report-analysis/SKILL.md          # Skill — workflow & rules chi tiết
```

## Cách dùng

1. **Mở VS Code** trong project có chứa các file trên
2. **Chọn agent** từ dropdown chat: `@Security Report Agent`
3. **Gõ prompt**:

# Lưu ý: Nên covert file dữ liệu sang định dạng .md để tối ưu trước khi phân tích

```
@Security Report Agent phân tích file.csv
@Security Report Agent tạo report từ data.csv lưu vào output/
@Security Report Agent tạo report với data.md kèm executive summary
```

Agent sẽ:
- Đọc dữ liệu → tính thống kê (total, unique IP/port/service, top lists)
- Phân tích pattern theo dịch vụ, banner, host concentration
- Sinh **Markdown** + **HTML** (CSS dashboard, Mermaid attack flow)
- Xác thực số liệu trước khi hoàn tất

## Output

| Định dạng | File | Nội dung |
|-----------|------|----------|
| Markdown | `{nguồn}-report.md` | 5 section SOC, tiếng Việt |
| HTML | `{nguồn}-report.html` | CSS grid, metric cards, risk badges, Mermaid CDN |
| Executive summary | `{nguồn}-executive-summary.md` | 1 trang, dashboard table + attack flow |

### Section order
1. **Overview** — campaign shape, key counts, expert judgment
2. **Campaign Metrics** — top IP, service, port, banner tables
3. **Trend Analysis** — service-driven clusters, no time-density
4. **Risk Assessment** — Critical → Info (impact × likelihood)
5. **Conclusion** — device type, main services, use cases, attack flow

## Tính năng chính

- **Evidence-first:** Mọi con số tính từ nguồn, không đoán
- **Vietnamese:** Toàn bộ report viết tiếng Việt
- **Expert reasoning:** Suy luận từ 6 tầng tín hiệu (port, banner, tổ hợp host, threat intel, điểm yếu, phân tán)
- **Risk framework:** 5 mức Critical/High/Medium/Low/Info theo impact × likelihood
- **Dual output:** `.md` cho nội dung + `.html` cho trình bày
- **Validation guard:** Instruction riêng kiểm tra consistency trước khi render

## Transfer

Copy 3 thư mục/file vào project khác:
```
.github/agents/
.github/instructions/
.agents/skills/soc-report-analysis/
```

VS Code tự động nhận agent, skill và instruction.

---

*Được xây dựng như một phần của SOC workflow tự động hóa.*
