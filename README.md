# 主控 Skill（Main Control）

让 AI 编程助手像一个**项目主控**那样工作：一个主对话只负责接需求和派活，每件事交给按业务域长期复用的执行会话去做，每次派发都带任务编号，执行和验收在执行会话里完成。

> Claude 桌面端新版 Projects 的思路是：一个项目是一场持续的对话，主对话为每件事分出一个线程。这和本 Skill 是同一个思路。本 Skill 早先是给 DeepSeek Harness 写的，现在也提供 Claude Code 版。

## 核心规则
1. **主控只派发，不亲自干活**：主控负责理解需求、维护规则、选执行会话、写一屏以内的派发说明；写代码、跑测试、生成产物都交给执行会话。
2. **按业务域长期复用执行会话**：容器按“支付”“订单履约”这类稳定的业务域划分，不按单个 bug 或前后端划分。同一个业务域只有一个容器，它是这些文件的唯一写入者，所以不会出现两个会话互相覆盖。
3. **忙也不开副本**：容器正在执行时，新任务照样发给它排队。
4. **每次派发带任务编号**（`T-YYMMDD-NN`），并登记台账；容器汇报的第一行必须带上这个编号。
5. **最小可交付闭环（MVP）**：每次只派一个能独立验收的结果，达到验收就停，不顺手扩展。
6. **派完就结束**：主控不轮询、不盯进度、不替容器动手；验收和修改由用户直接在执行会话里进行。
7. **状态写进文件**：主控、容器和台账登记在一个文件里，换会话、上下文被压缩都能恢复。

## 两个版本
| 目录 | 适用于 | 说明 |
|---|---|---|
| `claude-code/` | Claude Code（桌面端 / CLI） | `SKILL.md` + `MAIN_CONTROL.template.md`。用 `SendMessage` 续派、`start_session` 新建会话 |
| `dsh/` | DeepSeek Harness | 原版 `dsh-main-control`，附 3 个 Ruby 脚本：角色检测、绑定主控、Git worktree 只读预检 |

## 安装
**Claude Code**
1. 把 `claude-code/SKILL.md` 放到项目的 `.claude/skills/main-control/SKILL.md`（只对这个项目生效），或放到 `~/.claude/skills/main-control/SKILL.md`（所有项目都生效）。
2. 把 `claude-code/MAIN_CONTROL.template.md` 复制到项目根目录，改名为 `MAIN_CONTROL.md`，填上主控会话 id 和执行容器。
3. 在主控会话里说“你来当主控”，之后直接提需求即可。

**DeepSeek Harness**
1. 把 `dsh/` 放到 `~/.dsh/skills/dsh-main-control/`。
2. 在要当主控的会话里运行 `ruby ~/.dsh/skills/dsh-main-control/scripts/register_main_control.rb "$PWD" --name "<项目名>"`。

## 实际案例
一条短视频生产线用这套流程运行：
- 主控会话负责素材入库、数据复盘和派活；
- 「照片系列制作」「动画讲解制作」两个执行会话各管一个渲染引擎；
- 每条视频一个任务编号，执行会话交付后，作者直接在执行会话里验收和提修改。

## License
MIT
