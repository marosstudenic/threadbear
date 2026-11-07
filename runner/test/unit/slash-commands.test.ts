// docs/protocol.md, "Slash commands".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { makeHarness, tick, tmpDir } from '../helpers/fakes.ts';
import { PatchTrust } from '../../src/patch-trust.ts';
import type { CommandsRequest } from '../../src/adapters/types.ts';

const GRILL = { name: 'grilling', description: 'Grill the user' };

test("a thread's live session answers with its own list", async () => {
  const h = makeHarness();
  const cwd = tmpDir();
  const { thread } = h.runner.create({ text: 'hi', accountId: 'claude-3', cwd });
  await tick();
  let probed = 0;
  h.adapter.commands = async () => {
    probed++;
    return [];
  };
  h.adapter.last.commands = async () => [GRILL];
  assert.deepEqual(await h.runner.slashCommands({ threadId: thread.id }), { commands: [GRILL] });
  assert.equal(probed, 0);
  // Its CLI failing to answer falls back to a look in the folder.
  h.adapter.last.commands = async () => {
    throw new Error('gone');
  };
  assert.deepEqual(await h.runner.slashCommands({ threadId: thread.id }), { commands: [] });
  assert.equal(probed, 1);
});

test('with no live session, one look in the folder serves everyone for a minute', async () => {
  const h = makeHarness();
  const cwd = tmpDir();
  const asked: CommandsRequest[] = [];
  let answer!: (list: typeof GRILL[]) => void;
  h.adapter.commands = (req) => {
    asked.push(req);
    return new Promise((r) => (answer = r));
  };
  const a = h.runner.slashCommands({ cwd, accountId: 'claude-3' });
  const b = h.runner.slashCommands({ cwd, accountId: 'claude-3' });
  await tick();
  assert.equal(asked.length, 1, 'asked once for both');
  assert.equal(asked[0].cwd, cwd);
  assert.equal(asked[0].account.id, 'claude-3');
  assert.equal(asked[0].untrustedProjectSettings, undefined);
  answer([GRILL]);
  assert.deepEqual(await a, { commands: [GRILL] });
  assert.deepEqual(await b, { commands: [GRILL] });
  assert.deepEqual(await h.runner.slashCommands({ cwd, accountId: 'claude-3' }), { commands: [GRILL] });
  assert.equal(asked.length, 1, 'kept');
  // Another login or folder is another look.
  const other = h.runner.slashCommands({ cwd: tmpDir(), accountId: 'claude-3' });
  await tick();
  answer([]);
  await other;
  assert.equal(asked.length, 2);
  // A minute on, it looks again.
  const realNow = Date.now;
  Date.now = () => realNow() + 61_000;
  try {
    const again = h.runner.slashCommands({ cwd, accountId: 'claude-3' });
    await tick();
    answer([]);
    assert.deepEqual(await again, { commands: [] });
    assert.equal(asked.length, 3);
  } finally {
    Date.now = realNow;
  }
});

test('a failed look answers empty and is tried again next time', async () => {
  const h = makeHarness();
  const cwd = tmpDir();
  let n = 0;
  h.adapter.commands = async () => {
    n++;
    if (n === 1) throw new Error('no CLI');
    return [GRILL];
  };
  assert.deepEqual(await h.runner.slashCommands({ cwd, accountId: 'claude-3' }), { commands: [] });
  assert.deepEqual(await h.runner.slashCommands({ cwd, accountId: 'claude-3' }), { commands: [GRILL] });
});

test('Codex threads, missing folders and unknown logins get no list', async () => {
  const h = makeHarness();
  h.adapter.commands = async () => [GRILL];
  assert.deepEqual(await h.runner.slashCommands({ cwd: tmpDir(), accountId: 'codex-main' }), { commands: [] });
  assert.deepEqual(await h.runner.slashCommands({ cwd: path.join(tmpDir(), 'gone'), accountId: 'claude-3' }), { commands: [] });
  assert.deepEqual(await h.runner.slashCommands({ cwd: tmpDir(), accountId: 'nobody' }), { commands: [] });
  await assert.rejects(h.runner.slashCommands({ threadId: 'nope' }), /Thread not found/);
});

test("an untrusted folder is looked at with its settings' running parts left out", async () => {
  const root = tmpDir();
  const project = path.join(root, 'cloned');
  fs.mkdirSync(path.join(project, '.claude'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude', 'settings.json'), JSON.stringify({ hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'echo hi' }] }] }, permissions: { allow: ['Bash(ls)'] } }));
  const home = tmpDir();
  const h = makeHarness(home, {}, { panelsRoot: root, patchTrust: new PatchTrust({ file: path.join(home, 'patch-trust.json'), claudeHome: root }) });
  const asked: CommandsRequest[] = [];
  h.adapter.commands = async (req) => {
    asked.push(req);
    return [];
  };
  await h.runner.slashCommands({ cwd: project, accountId: 'claude-3' });
  assert.deepEqual(asked[0].untrustedProjectSettings, { permissions: { allow: ['Bash(ls)'] } });
});
