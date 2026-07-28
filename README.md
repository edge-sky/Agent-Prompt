一些用于工作流的提示词
# Agents
## Primary

### Fish

总所周知，鱼的记忆只有 7 秒(

那么作为一只只有 7 秒记忆的鱼，想要完成大工程，就需要将将记忆刻在**石头**上

作为主 Agent，他需要通过当读取前项目状态文件以决定如何处理新的 Query，通过调用子 Agent 完成问题分析、代码编写的工作，而其始终处于高位。在完成一次操作后，~~负责将本次工作的结果和发现**写回**状态文件～～暂时废弃，应考虑使用目录的方式

#### 状态流转
```
OBSERVE-->PLAN-->EXECUTE-->REVIEW
                    |       | 
                    |-------|
                      未通过
```

### Explore

如果说 Fish 是控制 Agents 去完成具体的任务，那么 Explore 面向的就是 User。它不会去编写任何的代码，而是帮助 User 快速获取项目当前的状态，便于快速了解当前代码逻辑与结构。

在不了解项目结构的情况下放任 AI 进行编码将会十分危险，但回滚的代价也不过是 token 的浪费)

## subagent

### plan-init

用于初始化项目，编写最初的状态文件

### Analyst

作为系统的眼睛，负责根据需求检索代码，并相应结论。它不会对代码进行直接修改，这不是它的工作，它将把分析的结构进行响应，由上层决定如何处理

### Worker

专注于解决问题的工具(人？)，负责严格按照计划对代码进行编写

### Reviewer
有干活的当然也有监工的，负责审查当前的更改是否达到既定的目标

### Sync

负责同步项目状态，以事实为基准，避免项目状态文件滞后

# Skills

## tdd-workflow

测试驱动开发(TDD) 工作流，使用此技能以要求 Agent 遵循 RED-GREEN-REFACTOR 循环，通过测试先行的方式锚定目标，并以通过测试的最小实现为目标，尽可能保证代码可控

# 同步到 OpenCode 全局配置

仓库根目录的 `sync-to-opencode.sh` 可以把这里的 Agent、Skill 和本地 Plugin **复制**到 OpenCode 的全局配置目录。脚本根据自身位置解析仓库的绝对路径，因此仓库不需要放在 OpenCode 配置目录中。

无参数运行时，脚本会显示菜单，可选择同步全部内容或单独同步 `agents`、`skills`、`plugins`：

```bash
./sync-to-opencode.sh
```

也可以直接通过参数选择同步范围；分类参数可以组合：

```bash
./sync-to-opencode.sh --all
./sync-to-opencode.sh --agents
./sync-to-opencode.sh --agents --skills
./sync-to-opencode.sh --plugins
```

默认目标目录为 `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`。如需使用其他 OpenCode 配置目录，必须传入绝对路径：

```bash
./sync-to-opencode.sh --all --target-dir /absolute/path/to/opencode
```

## 为 Agent 分配三级模型

选择同步 `agents`（包括 `--all`）时，脚本会调用目标配置目录对应的 `opencode models --pure`，并在输入框上方列出已经识别、可直接配置的 `provider/model`。模型分为三级，**一级是能力最强的模型，向后依次递减**：

- 一级：`Fish`、`Reviewer`
- 二级：`Analyst`、`Explore`、`Worker` 以及其他未明确归类的 Agent
- 三级：`Sync`、`plan-init`

脚本依次请求三个级别的模型，例如：

```text
一级模型（Fish、Reviewer，输入完整 provider/model，留空跳过）: openai/gpt-5.5
二级模型（Analyst、Explore、Worker 及其他 Agent，输入完整 provider/model，留空跳过）: github-copilot/gpt-5.4-mini
三级模型（Sync、plan-init，输入完整 provider/model，留空跳过）: omlx/gemma-4-e4b-it-4bit
```

输入必须使用列表中的完整 `provider/model`；留空只跳过对应级别的模型注入。若源 Agent 已有 `model:`，选择模型后会更新该字段；如果留空，则源配置保持不变。模型配置仅写入复制后的目标 Agent，不修改仓库中的源文件。若无法运行 OpenCode 模型发现，脚本会提示，并允许手动输入合法的 `provider/model`。

目标分类目录不存在时会自动创建。新文件直接复制；如果目标中已经存在同一路径的文件，脚本会对每个文件分别询问是否覆盖，只有输入 `y` 或 `Y` 才会覆盖，其他输入默认跳过。同步不会删除目标目录中的额外文件，也不会移动或修改仓库中的源文件。

当前仓库尚无 `plugins/` 目录；选择插件或全量同步时会提示并安全跳过，未来新增本地 JS/TS 插件后无需修改脚本。

运行集成测试：

```bash
./tests/test-sync-to-opencode.sh
```
