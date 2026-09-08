---
name: ember-coordinator-handoff
description: Prepares and verifies a smooth transfer between main Ember coordinator chats. Use when the user asks to migrate, replace, rotate, or create a successor for a long main Ember chat, or when the current coordinator recommends such a transition.
---

# Ember Coordinator Handoff

Use this workflow to change the main coordinator without asking the user to
rebuild project context or working rapport manually.

## Границы

- Do not create a successor task until the user explicitly agrees to the move.
- Do not rotate during implementation, acceptance, or correction of an active
  Task Contract unless the current coordinator is genuinely unable to continue.
- The repository is the technical source of truth; conversation summaries add
  intent and rapport but never override code, tests, Git, or canonical docs.
- The successor performs no implementation during orientation.
- Keep the old coordinator available until the user accepts the successor.

## 1. Стабилизировать текущее состояние

Before preparing the successor:

1. Read `AGENTS.md` and `docs/EMBER_NOW.md`.
2. Check `git status --short`, the current branch, remote and recent commits.
3. Identify whether each uncommitted file belongs to an accepted slice, an
   unfinished contract, or unrelated user work. Do not merge those categories.
4. Update `EMBER_NOW.md` and only the canonical documents affected by accepted
   decisions. Commit or push only when the user explicitly requests it.
5. If a contract remains unfinished, describe its exact state and keep the old
   coordinator responsible until the user approves an exceptional mid-contract
   transfer.

## 2. Подготовить промпт преемника

Keep it concise but include all of these fields:

```text
Role: You are the new main coordinator for Ember, not an implementation worker.

Technical source of truth:
- repository and current checkout;
- exact branch/checkpoint and categorized working-tree state;
- AGENTS.md, EMBER_NOW.md and only the relevant canonical sections;
- current owners and verification gates.

Product and game-design north star:
- the experience the user is trying to create;
- accepted reference games and what Ember borrows from each;
- accepted mechanics relevant to the current milestone;
- explicit exclusions and unresolved design choices.

Working relationship:
- explain engineering decisions in plain Russian without talking down;
- recommend before listing alternatives and explain their consequences;
- ask the user only about game feel, visual direction, scope or expensive
  boundaries; decide routine reversible engineering details yourself;
- show progress without dumping raw command logs;
- announce worker model and reasoning effort before delegation.

Coordination policy:
- discuss and approve Task Contracts in the main chat;
- delegate one writing worker at a time in the current checkout by default;
- workers report to the coordinator directly;
- reuse complete targeted-test evidence and run only missing gates;
- manual Godot acceptance remains with the user;
- commit/push only after explicit authorization.

Current position:
- last accepted player-visible result;
- checks and manual acceptance already completed;
- next likely slice, but do not start it yet;
- known risks, blockers and decisions still open.

Orientation task:
Read and verify the repository. Do not edit files, run destructive commands,
create a worker, commit or push. Return the synchronization report below.
```

Never put secrets, transient raw logs or unsupported guesses in this prompt.

## 3. Создать и проверить преемника

After explicit user approval of the handoff itself, ask the user to approve one
of these launch modes; do not choose silently:

- the current local checkout, with an explicit warning that the successor will
  share its exact categorized uncommitted state;
- an isolated worktree whose starting state is `working-tree`, so it includes
  the current checkout and all categorized uncommitted changes rather than only
  the last commit.

Create the new task in the same Ember project only after that launch-mode
consent. Include the categorized working-tree state in the successor prompt,
send it, and wait for its orientation response.

Require this exact report structure:

```text
Понимание Ember:
- игровая цель и важные референсы;
- текущий milestone и последний принятый результат.

Техническая точка:
- branch/checkpoint;
- рабочее дерево по категориям;
- существующие owners и обязательные gates.

Как я буду работать с пользователем:
- стиль объяснений и вопросы, которые действительно требуют его решения;
- схема coordinator/worker и проверки.

Следующий вероятный контракт:
- цель и предполагаемые границы, без начала реализации.

Неясности или противоречия:
- только реально найденные расхождения.
```

## 4. Проверить и исправить понимание

Compare the response with Git, `EMBER_NOW.md`, relevant canonical docs and the
current conversation decisions. Send corrections directly to the successor.
Do not make the user act as a messenger while a parent/task communication channel
is available. Recheck only corrected or previously missing parts.

The successor is ready when it:

- names the real current checkpoint and separates dirty-tree ownership;
- explains the game direction and relevant references without inventing rules;
- matches the user's preferred level and tone of communication;
- understands that it coordinates rather than implementing directly;
- proposes no code before a newly approved Task Contract.

## 5. Завершить передачу

Tell the user what the successor understood, any corrections that were needed,
and why the transition is safe. Open or link the new task for the user. Keep the
old task unarchived until the user confirms that the new coordinator feels right;
then archive it only if the user asks.
