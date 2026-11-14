---
title: "NexusCore M2：Bot 管理与插件运营的落地"
date: 2026-11-14
draft: false
tags: ["NexusCore", "Go", "系统设计", "开源观察"]
categories: ["系统设计"]
summary: "合并解读 NexusCore 的 M2 提交，梳理 Bot 管理、配置审批、插件生命周期与两级进程模型如何连成一条可运营链路。"
---

NexusCore 的 M2 提交把项目从“内核 MVP”推进到了“可运营”。以 `d569a80` 和 `8b627bf` 两组提交为参考，这次更新的重点不是单点功能，而是把 Bot 创建、配置变更、插件生命周期和进程管理串成一条闭环。

## 提交概览

| 提交 | 主要内容 | 作用 |
| --- | --- | --- |
| `d569a80` | Bot 管理 CLI、配置中心审批流、插件生命周期、两级进程模型、M2 冒烟脚本 | 建立完整的运营链路 |
| `8b627bf` | 进程防复用、配置终端约束、因果链闭环、更多测试 | 收口安全边界和正确性 |

这组提交共涉及约 6100 行代码改动，其中 `d569a80` 新增了插件管理、HTTP API、插件进程表和 M2 冒烟链路；`8b627bf` 则在这些功能之上补齐了进程身份校验、配置审批的强校验和全链路因果追踪。

## Bot 管理与配置中心

M2 给 CLI 增加了 `bot create / bot list / bot enable` 和 `create-bot pull`。`user_writer_bot` 这类用户自建 Bot 默认携带 `personal_stack_v1` 记忆档案，而普通 worker Bot 默认不带。这个区分放在 CLI 层就定下来，避免后续把记忆能力误当作 Bot 的固有属性。

配置中心也补齐了完整审批流：`propose → review → approve → activate → rollback`。审批不再只是一个状态切换，而是绑定 diff 和 checksum。冒烟脚本里专门验证了错误 checksum 会被拒绝，确保审批对象和用户确认的内容一致。

## 插件生命周期与两级进程

插件从安装到下线走的是标准生命周期：`install → security-approve → upgrade → disable → uninstall`。安装时校验 manifest 和 `binary_digest`，审批通过后才把插件状态推进到 `enabled`，再由 supervisor 调和启动对应的 owner Bot。

进程模型分成了两级。Bot 进程是内核 supervsor 管理的一级；插件进程由插件声明的 owner Bot 负责启动和回收，这是二级。这带来的好处是插件进程不需要直接接入内核总线，只需要上报 PID、PGID、`pid_start_time` 等信息，由 supervisor 统一处理孤儿回收和强制终止。

`8b627bf` 进一步加上了 `pid_start_time` 双匹配和 `SignalProcessGroup` 校验，避免误伤 PID 复用后的新进程。`plugin ps / stop / start / kill --confirm` 也把进程的运行态和停止模式暴露给 CLI，方便运维和验收。

## 冒烟链路

M2 的验收走的是 `make smoke-m2`，覆盖了数据库迁移、Bot 创建、配置审批、插件安装、插件进程启停、孤儿回收和 DLQ 操作。这类脚本的价值在于，它把设计文档里的边界条件拉到真实命令链路上验证，而不是只停在架构描述上。

## 小结

M2 的核心变化是让 NexusCore 从内核能力变成可运营系统。Bot、配置、插件、进程四个面在这次更新里连在一起，后续如果要继续往 M3 推进，尤其是记忆插件和群聊插件，这些边界已经搭好了基础。
