# wafer dse 迁移记录（2026-11-06）

## 一、结论

1. 三个仓已迁入 `/home/walker/work/07-projects/wafer-dse/`，分别命名为 `model/`、`code/`、`paper/`。
2. 每仓保留各自 `.git` 与远端；未做 subtree、未 squash、未改写历史、未使用 force push。
3. 文件数与字节数移动前后一致；三仓 `git fsck` 无错误。
4. `model/` 的 3 个 commit 未到达 GitHub origin；本机无 GitHub 凭据。Gitea 镜像已有同一 HEAD。
5. `/home/walker/booksim2` 未被三仓引用，未移动。
6. `/home/walker` 下已无 `wafer-dse*` 顶层目录。

## 二、路径与文件数对照

| 原路径 | 新路径 | 字节数（前/后） | 文件数（前/后） | 目录数（前/后） |
|---|---|---|---:|---:|
| `/home/walker/wafer-dse` | `/home/walker/work/07-projects/wafer-dse/model` | 299,177,711 / 299,177,711 | 1,132 / 1,132 | 352 / 352 |
| `/home/walker/wafer-dse-code` | `/home/walker/work/07-projects/wafer-dse/code` | 99,964,657 / 99,964,657 | 2,602 / 2,602 | 505 / 505 |
| `/home/walker/wafer-dse-paper` | `/home/walker/work/07-projects/wafer-dse/paper` | 66,991,516 / 66,991,516 | 934 / 934 | 334 / 334 |

## 三、Git 与远端

| 目录 | HEAD | commit 总数 | 移动前未推送 | `git ls-remote origin` | 其他远端 |
|---|---|---:|---:|---|---|
| `model/` | `0db6e60f59da97c1bcf9a1cebbf8baa8feb9c487` | 42 | 3 | `e393bb1e213837e018a9cab22cef488720faf16a`（GitHub，落后 3） | Gitea `0db6e60f59da97c1bcf9a1cebbf8baa8feb9c487`（一致） |
| `code/` | `1db6b8b672041e0db901b7b9c4210d5106b6fadd` | 16 | 0 | `1db6b8b672041e0db901b7b9c4210d5106b6fadd` | 无 |
| `paper/` | `3d3da7d3e1726432b7ef1d697f0588c8ff5ad60d` | 48 | 0 | `3d3da7d3e1726432b7ef1d697f0588c8ff5ad60d` | 无 |

`model/` 未到达 GitHub 的 3 个 commit：

1. `0db6e60` feat: V6 模型（die+wafer 两级）与 cvxpy 求解实现
2. `8b2d77f` refactor: 删除 V5 LP 引擎与旧配置
3. `af47b21` docs: 新增晶圆级交换机 DSE 数理模型报告

推送尝试与结果：`git push origin main` 返回 `could not read Username for 'https://github.com'`；`ssh -T git@github.com` 返回 `Permission denied (publickey)`。Gitea 镜像 `http://127.0.0.1:8443/walker/wafer-dse.git` 的 `refs/heads/main` 已等于本地 HEAD，3 个 commit 已存在于该远端。

## 四、引用点修改

共修改 83 个文件、440 行。外部活文档 46 个文件、317 行；项目内 37 个文件、123 行（批量 33 个文件、119 行，另手工 4 个文件、4 行）。替换规则：

| 原写法 | 新写法 |
|---|---|
| `/home/walker/wafer-dse-code` | `/home/walker/work/07-projects/wafer-dse/code` |
| `/home/walker/wafer-dse-paper` | `/home/walker/work/07-projects/wafer-dse/paper` |
| `/home/walker/wafer-dse` | `/home/walker/work/07-projects/wafer-dse/model` |
| `~/wafer-dse-code` | `~/work/07-projects/wafer-dse/code` |
| `~/wafer-dse-paper` | `~/work/07-projects/wafer-dse/paper` |
| `~/wafer-dse` | `~/work/07-projects/wafer-dse/model` |
| `../wafer-dse`（`paper/` 内） | `../model` |

逐文件清单：

| 文件 | 行 |
|---|---|
| `code/deliverable/ch3-overview/v4/sections/03-overview/01-bandwidth-promise/01-service-conditions.tex` | 2 |
| `code/verify/paper/sections/03-overview/01-bandwidth-promise/01-service-conditions.tex` | 2 |
| `paper/AGENTS.md` | 14 |
| `paper/tools/check-env.sh` | 9,12 |
| `work/00-secretariat/dispatch/nodes/reviewers.yml` | 8 |
| `work/00-secretariat/dispatch/nodes/外审模拟-节点规格-v1.md` | 307,867–869 |
| `work/00-secretariat/dispatch/nodes/评审-节点规格-v1.1.md` | 1164,1237 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/docs/专题-设计到大纲-v1.md` | 351,795 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/docs/大纲模板-v1.md` | 15 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/docs/岗位装填表-v1.md` | 5,7,68–70,77–83,189–193,201–207,325,342,390 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/docs/岗位装填表-v1.yml` | 8–9,28,40,49,186,196,208,220,226 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/docs/科研产线-总调规程-v1.md` | 339 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/history/docs/文本生产流水线-v0.1.md` | 18–19,54,204,208,324 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/nodes/评审-节点规格-v1.1.md` | 1164,1237 |
| `work/00-secretariat/dispatch/pipeline-workflow-repo/tools/citation-lint-自检-2026-11-04.md` | 93–94,102 |
| `work/00-secretariat/dispatch/专题-设计到大纲-v1.md` | 351,795 |
| `work/00-secretariat/dispatch/产线节点清单/节点清单-2026-11-04.csv` | 6 |
| `work/00-secretariat/dispatch/产线节点清单/节点清单-2026-11-04.md` | 45 |
| `work/00-secretariat/dispatch/大纲模板.md` | 15 |
| `work/00-secretariat/dispatch/岗位装填表-v1.md` | 5,7,68–70,77–83,189–193,201–207,325,342,390 |
| `work/00-secretariat/dispatch/岗位装填表-v1.yml` | 8–9,28,40,49,186,196,208,220,226 |
| `work/00-secretariat/dispatch/文本生产流水线-v0.1.md` | 18–19,54,204,208,324 |
| `work/00-secretariat/dispatch/科研产线-总调规程-v1.md` | 339 |
| `work/04-ops/fonts/consolas-结论.md` | 23 |
| `work/04-ops/tools/map/00-索引.md` | 31–33 |
| `work/04-ops/tools/节点装配表/build_three.py` | 55–56 |
| `work/04-ops/tools/节点装配表/build_v2_skillfill.py` | 43,55,67,91–92 |
| `work/04-ops/tools/节点装配表/三件套登记表-2026-11-04-v2.csv` | 3–5,7–8,10,25,35–36,38,44–47,53–56,64–66 |
| `work/04-ops/tools/节点装配表/三件套登记表-2026-11-04-v2.md` | 12–14,16–17,19,34,44–45,47,53–56,62–65,73–75,86–88,90 |
| `work/04-ops/tools/节点装配表/三件套登记表-2026-11-04.csv` | 3–7,9,24,34–35,37,43–46,52–55,63–65 |
| `work/04-ops/tools/节点装配表/三件套登记表-2026-11-04.md` | 10–14,16,31,41–42,44,50–53,59–62,70–72 |
| `work/04-ops/tools/节点装配表/散落清单-2026-11-04.csv` | 9–10,37–38,58,68–69,71–72,75,78 |
| `work/04-ops/tools/节点装配表/散落清单-2026-11-04.md` | 36,98,108,111–112,126–131,145–146,180–183 |
| `work/04-ops/tools/节点装配表/装配表-v2-S0-S5-技能重填.csv` | 3–5,7 |
| `work/04-ops/tools/节点装配表/装配表-v2-S0-S5-技能重填.md` | 31–33,35 |
| `work/04-ops/tools/节点装配表/论文产线-节点装配表-v1.md` | 48 |
| `work/04-ops/tools/节点装配表/诚实表-A.csv` | 4,6–7,9 |
| `work/04-ops/tools/节点装配表/诚实表-A.md` | 24,26–27,29,59,61,75,77,83,85,99,101,200 |
| `work/04-ops/tools/节点装配表/诚实表-B.md` | 108,124 |
| `work/04-ops/tools/节点装配表/详表-A-S0-S4.csv` | 15,22,29,37,43,47,52,57,62 |
| `work/04-ops/tools/节点装配表/详表-A-S0-S4.md` | 57,63–66,72–75 |
| `work/04-ops/tools/节点装配表/详表-B-S5-S8.csv` | 3,18,28–29 |
| `work/04-ops/tools/节点装配表/详表-B-S5-S8.md` | 82,102,119–120 |
| `work/04-ops/tools/节点装配表/详表-C-S9-S11.csv` | 2–3,5,8–9 |
| `work/04-ops/tools/节点装配表/详表-C-S9-S11.md` | 15–16,18,31–32 |
| `work/04-ops/tools/节点装配表/详表-D-AO-图股.csv` | 6–9 |
| `work/04-ops/tools/节点装配表/详表-D-AO-图股.md` | 67–70,118,132 |
| `work/06-discipline/specs-repo/code-style/CODE-STYLE-NOTE.md` | 4,9,15 |
| `work/06-discipline/specs-repo/code-style/CODE-STYLE-ONEPAGE.md` | 3 |
| `work/07-projects/wafer-dse/code/README.md` | 8–11 |
| `work/07-projects/wafer-dse/code/config/material/material_prop.yml` | 3 |
| `work/07-projects/wafer-dse/code/deliverable/ch3-overview/INSTALL.md` | 3,11 |
| `work/07-projects/wafer-dse/code/deliverable/ch3-overview/v4/sections/03-overview/01-bandwidth-promise/01-service-conditions.tex` | 2 |
| `work/07-projects/wafer-dse/code/deliverable/ch3-overview/v4/sections/03-overview/01-bandwidth-promise/03-rating-definition.tex` | 2 |
| `work/07-projects/wafer-dse/code/exp/figures_all.py` | 29 |
| `work/07-projects/wafer-dse/code/exp/frontier_figure.py` | 33 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/README.md` | 298,317 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/map_inputs.py` | 10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/fullmesh4/design_tr.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/fullmesh4/design_uni.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/kary2x4/design_tr.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/kary2x4/design_uni.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/mesh3/design_tr.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/mesh3/design_uni.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/mesh4/design_tr.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/mesh4/design_uni.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/torus3/design_tr.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/torus3/design_uni.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/torus4/design_tr.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/exp/rc_benchmark/rc_inputs/torus4/design_uni.json` | 3–7,9–10 |
| `work/07-projects/wafer-dse/code/src/physical/extract/mfit.py` | 4,24 |
| `work/07-projects/wafer-dse/code/verify/paper/sections/03-overview/01-bandwidth-promise/01-service-conditions.tex` | 2 |
| `work/07-projects/wafer-dse/code/verify/paper/sections/03-overview/01-bandwidth-promise/03-rating-definition.tex` | 2 |
| `work/07-projects/wafer-dse/model/notes/MATH_MODEL_REPORT.md` | 5,36,359 |
| `work/07-projects/wafer-dse/model/notes/MATH_MODEL_V6.md` | 273,279 |
| `work/07-projects/wafer-dse/paper/AGENTS.md` | 16,48–49 |
| `work/07-projects/wafer-dse/paper/HANDOFF.md` | 3,81 |
| `work/07-projects/wafer-dse/paper/README.md` | 4,31 |
| `work/07-projects/wafer-dse/paper/paper/sections/06-discussion/01-screening-boundary.tex` | 4 |
| `work/07-projects/wafer-dse/paper/paper/sections/06-discussion/02-future-work.tex` | 4 |
| `work/07-projects/wafer-dse/paper/planning/outline/outline.md` | 209 |
| `work/07-projects/wafer-dse/paper/tools/paper-gate.py` | 24–25 |
| `work/dispatch/pipeline-workflow-repo/node-spec/外审模拟-节点规格-v1.md` | 307,867–869 |

## 五、booksim2 判定

1. 结论：未移动，仍在 `/home/walker/booksim2`。
2. 证据一：以 `/home/walker/booksim2`、`~/booksim2`、`../booksim2` 三种写法检索三个仓，命中 0。
3. 证据二：`booksim2/README.md` 自述其独立于论文仓与 wafer-dse 仓，不参与 git 同步；引用方向是 booksim2 指向 `wafer-dse-paper` 的评测章，而非三仓指向 booksim2。
4. 证据三：`booksim2` 为 161M、909 个文件的工作区，顶层不是 git 仓，内部含两个独立 `.git`（`booksim2/booksim2`、`booksim2/rapidchiplet`）。
5. 处置：按「不被引用就别动」执行；未改其内容与路径引用。

## 六、README 与登记

1. 项目首页：`/home/walker/work/07-projects/wafer-dse/README.md`。
2. 项目登记：`/home/walker/work/07-projects/LEDGER.csv` 增 1 行，项目名 `wafer dse`，产物路径指向项目根。
3. 项目根不是 git 仓；README 与本记录不被任一子仓跟踪。

## 七、暂缓项

| 项 | 位置 | 读者 | 原因 |
|---|---|---|---|
| 归档中的旧路径 5 文件 13 行 | `/home/walker/work/03-archive/` | 查 2026-11-04 盘点与归档的人 | 历史快照，改写会伪造当时路径 |
| 冻结副本中的旧路径 5 文件 7 行 | `/home/walker/work/06-discipline/specs-outside-2026-11-05/` | 06 纪律部 | 2026-11-05 冻结副本，非活文档 |
| 数据采集记录中的旧路径 5 文件 6 行 | `paper/notes/data/data-raw/` | 论文数据溯源者 | 记录采集当时的工作目录，属证据 |
| 旧运行日志 20 行 | `model/exp/mesh_curve_report.txt` | 查旧实验输出的人 | 已捕获的运行日志，非活引用 |
| venv 创建记录 1 行 | `model/.venv/pyvenv.cfg` | 查虚拟环境来源的人 | 环境元数据；venv 移动后仍可用 |
| agent 会话日志 13 文件 | `code/.codex-home/` | 查 2026-10 agent 会话的人 | 会话历史，非活引用 |
| GitHub 推送 3 commit | `model/` 的 GitHub origin | 需要 GitHub 副本的人 | 本机无 GitHub 凭据；Gitea 镜像已有 |

## 八、工作区状态

| 目录 | 迁移前 `status --porcelain` 条数 | 迁移后条数 | 说明 |
|---|---:|---:|---|
| `model/` | 7 | 8 | 新增 1 个被改路径的已跟踪文件 |
| `code/` | 37 | 39 | 新增 2 个被改路径的已跟踪文件 |
| `paper/` | 58 | 60 | 新增 2 个被改路径的已跟踪文件 |

上述改动均未提交；迁移未替任何仓创建 commit。
