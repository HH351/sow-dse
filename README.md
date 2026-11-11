# wafer dse

晶圆级交换机设计空间探索项目。以线性规划判定给定拓扑、布局与物理参数下的最大可承诺出入口带宽 B*。

## 一、子目录职责

1. `model/`：模型规范与主实现仓，含 V6 数理模型、LP 引擎、测试与实验编排。
2. `code/`：论文第三章的简化重实现，含 cvxpy 求解、物理参数单一来源与 DSENT/MFIT 校验脚本。
3. `paper/`：ISCA 英文论文仓，含大纲、正文、图与 BibTeX。

## 二、远端

| 目录 | 远端 |
|---|---|
| `model/` | `https://github.com/WalkerDongGithub/wafer-dse.git`；镜像 `http://127.0.0.1:8443/walker/wafer-dse.git` |
| `code/` | `http://127.0.0.1:8443/walker/wafer-dse-code.git` |
| `paper/` | `http://127.0.0.1:8443/walker/wafer-dse-paper.git` |

## 三、入口命令

1. 模型求解：`cd model && make run`。
2. 模型测试：`cd model && make test`。
3. 简化实现校验：`cd code && PYTHONPATH=src python3 -B exp/design_point_check.py`。
4. 论文构建：`cd paper && make build-tectonic`；产物为 `paper/build-acm/main-acm.pdf` 与 `paper/build-ieee/main-ieee.pdf`。
5. 迁移记录：`MIGRATION-2026-11-06.md`。

## 四、当前状态

1. 三仓各自保留 `.git` 与远端；历史未改写，未使用 subtree 或 squash。
2. `model/` 在 `main`，HEAD `0db6e60`，42 commits；Gitea 镜像 HEAD 与本地一致；GitHub origin 停在 `e393bb1`，3 个 commit 未推送，本机无 GitHub 凭据。
3. `code/` 在 `main`，HEAD `1db6b8b`，16 commits，远端 HEAD 一致。
4. `paper/` 在 `main`，HEAD `3d3da7d`，48 commits，远端 HEAD 一致。
5. 三仓工作区均有未提交改动；本次迁移的引用路径改写亦未提交。
6. `/home/walker/booksim2` 未被三仓引用，未并入本项目。
