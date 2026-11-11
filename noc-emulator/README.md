# Trace NoC FPGA

`xc7k480tffg1156-2` 上的 **8×8 mesh、2 VC、每 VC 深度 8、100 MHz 物理时钟**。完整 trace 预装 DDR 后自主执行，DDR 等待和内部流水暂停不推进逻辑时间。固件支持每次任务切换 YX DOR 或两段 YX Valiant；Valiant 的两段使用不同半组 VC，mid 由 Host 指定。

`rtl/`、`board/ypcb/`、`config/default.tcl` 用于固件构建；`studio_backend/` 包含流量生成、坐标映射、DMA 和统计，全部编入一个 `libnoc_studio.so.1`。构建产物位于 `build/`。

## 构建与使用

Host 依赖 CMake ≥3.20、C++20 编译器、`nlohmann-json3-dev`；板卡使用 XDMA 驱动。项目文件路径均相对脚本所在目录。

```bash
./build.sh                    # 默认仅构建 Studio 动态库
sudo ./build.sh access        # 用 ACL 授权 sudo 调用者访问 XDMA，需要 acl 软件包
../studio/run.sh              # 在“现实基座验证”选择 FPGA、流量和路由
```

库位置为 `build/host/lib/libnoc_studio.so.1`，Studio 可通过 `NOC_STUDIO_LIBRARY` 覆盖。默认设备为 `/dev/xdma0_h2c_0` 和 `/dev/xdma0_c2h_0`，可通过 `NOC_XDMA_H2C` / `NOC_XDMA_C2H` 覆盖。设备独占，单个任务等待上限 60 秒；超时不会取消硬件任务。

固件使用 Vivado 2025.2；将 `vivado` 加入 PATH，或设置 `VIVADO_SETTINGS` 指向其 `settings64.sh`。

```bash
./build.sh firmware 16        # 综合、布局布线、生成 bitstream
./build.sh all 16             # 一次构建动态库和固件
./build.sh program            # JTAG 下载 build/board/noc_emulator.bit
sudo ./build.sh rescan BDF    # BDF 使用 lspci -D -d 10ee:7028 查询的 PCI 地址
sudo ./build.sh access        # 重新枚举后再次授权
```

板级工程、routed checkpoint、资源及时序报告位于 `build/board/`，setup/hold slack 均非负才生成 bitstream。`program` 可指定其他 bitstream 路径，仅通过 JTAG 下载。

## Studio 接口

公开头文件为 `studio_backend/include/noc_studio.h`，仅导出三个 C ABI：

- `noc_studio_v1_run(request_json, &response_json)`：同步执行，返回 0 表示成功；失败返回非零及 `{"error":...,"code":...}`。
- `noc_studio_v1_free(response_json)`：释放每个非空返回字符串。
- `noc_studio_v1_capabilities()`：返回静态 JSON 字符串，无需释放。

请求字段：

| 字段 | 含义 / 默认值 |
|---|---|
| `rows, cols` | 必填，分别为 1～8，至少两个节点 |
| `transform, origin_row, origin_col` | 默认 `1,0,0`；transform 位：转置=1、行翻转=2、列翻转=4，按此顺序变换后偏移，必须落在 8×8 内 |
| `routing` | `dor`（默认）、`valiant`、`valiant_terminal` |
| `traffic` | `worst_perm`（默认）、`custom`、`uniform`、`randperm`、`bitcomp`、`transpose`、`bitrev`、`shuffle`、`tornado`、`neighbor`、`diagonal`、`hotspot` |
| `terminals, permutation, od` | 模型流量的节点集合、terminal 序号置换、OD 权重矩阵；worst_perm 优先使用置换，custom 使用 OD |
| `sample_period, warmup_periods, max_samples` | 默认 `1000,3,10` |
| `injection_rate, seed` | 默认 `0.1,42` |
| `l_star, B_star, requirement, model_source` | 可选，Studio 模型比较信息 |

节点编号为 `row*cols+col`。Studio 默认转置坐标，使逻辑 XY 对应固件 YX，支持 8×8 以内的非环绕 mesh；翻转和偏移可用于子网映射。`valiant` 在逻辑 mesh 均匀抽取 mid，`valiant_terminal` 在 terminals 中抽取，允许 mid 等于 src 或 dst。

流量在 C++ 内生成，使用单 flit 包、Bernoulli 注入和独立的时间/目的/mid 随机序列。模型流量仅 terminals 注入，其他流量使用全部逻辑节点；OD 行和/最大行和决定源强度，行内权重决定目的概率。transpose 要求方形 mesh，bitrev/shuffle 要求节点数为 2 的幂。围绕 `1/max(l_star)` 或 `injection_rate` 扫描 12 个注入率点，单 trace 上限 800 万包。

响应直接对应 Studio `SimResult`：`metrics`、`series`、`comparison` 等。逐包数组留在 C++ 内存中；`series` 返回时延、窗口接收率、排队量、最终逻辑周期、链路计数和各阶段墙上时间。

令 `W=sample_period*warmup_periods`、`T=sample_period*max_samples`：trace 发送窗口为 `[0,W+T)`；时延统计 `[W,W+T)` 发送的包，接收率统计 `(W,W+T]` 完成的包并除以 T 和声明的源节点数。链路统计包括预热、测量和排空，`metrics.links` 与 `series[i].link_stats` 一一对应，计数顺序为 flits/heads/blocked/contended。无法观测的实际注入率、纯网络时延返回 null；有限窗口饱和观测不自动判定模型 soundness。

## FPGA DDR 协议

全部字段为 little-endian。`C=0x00100000`，N 为事件数，`align4K` 为向上对齐 4096B。

| 区域 | 地址 | 格式 |
|---|---|---|
| command | C | 16B：`magic:u64, event_count:u32, routing:u32` |
| status | C+16 | 16B：`state:u16, error:u16, completion_count:u32, logical_cycle:u64` |
| source counts | C+32 | 64 个 u32，共 256B |
| events | E=C+4096 | 每条 16B：`send_time:u64, dst:u16, mid:u16, flit_num:u32` |
| completion | P=align4K(E+16*N) | 每条 16B：`packet_key:u64, completion_cycle:u64` |
| link stats | S=align4K(P+16*N) | 每条 32B：`flits:u64, heads:u64, blocked:u64, contended:u64` |

magic=`0x314c554d45434f4e`；routing：DOR=0、Valiant=1；state：IDLE=1、RUNNING=2、DONE=3、ERROR=4。error：NONE=0、BAD_MAGIC=1、BAD_ROUTING=2、BAD_RANGE=5、AXI_READ=8、AXI_WRITE=9、AXI_RLAST=10、INTERNAL=11。常量见 `rtl/engine/noc_emulator_protocol_pkg.sv`。

事件按物理 source 分组，组内按时间排列，source 由计数表推导；packet_key 是事件区序号。src/dst 必须不同，flit_num 至少为 1，DOR 的 mid 填 dst。地址范围要求 `align4K(S+352*32) <= 0x80000000`。

Host 独占设备，先读 command 再读 status 确认空闲；清旧 status 为 IDLE，上传 counts 和全部 events，最后单独提交 16B command。FPGA 先发布 RUNNING 再清命令，完成全部写回后才发布 DONE。控制事务 16B 对齐，大数据批量 DMA；主机缓冲区低地址位与 DDR 地址匹配。无需清空结果区，回读仅覆盖已写入字节，不补读整页，以免触发未初始化 DDR ECC。

352 条链路顺序：64 条 injection、按行排列的水平邻接边（每对向右/向左）、按行排列的垂直邻接边（每对向下/向上）、64 条 ejection。flits/heads 为传输数，blocked 为有需求但未传输的逻辑周期数，contended 为存在多个需求的逻辑周期数；最终统计固定占 11 KiB。
