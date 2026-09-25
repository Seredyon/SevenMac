const test = require('node:test');
const assert = require('node:assert/strict');
const check = require('./release_check.cjs');

function fixture({ release, object, error, annotated } = {}) {
  const outputs = {};
  const missing = () => { throw Object.assign(new Error('Missing'), { status: 404 }); };
  return {
    outputs,
    args: {
      version: '1.3', context: { repo: { owner: 'owner', repo: 'repo' }, sha: 'tested' },
      core: { setOutput: (k, v) => { outputs[k] = v; }, info: () => {} },
      github: { rest: {
        repos: { getReleaseByTag: async () => {
          if (error) throw error;
          return release ? { data: release } : missing();
        } },
        git: {
          getRef: async () => object ? { data: { object } } : missing(),
          getTag: async () => ({ data: { object: annotated } })
        }
      } }
    }
  };
}
test('new version is eligible', async () => {
  const f = fixture(); await check(f.args); assert.equal(f.outputs.publish, 'true');
});
test('published release is never replaced', async () => {
  const f = fixture({ release: { draft: false } });
  await check(f.args); assert.equal(f.outputs.publish, 'false');
});
test('draft at tested commit can be retried', async () => {
  const f = fixture({ release: { draft: true }, object: { type: 'commit', sha: 'tested' } });
  await check(f.args); assert.equal(f.outputs.publish, 'true');
});
test('a tag at another commit blocks publication', async () => {
  const f = fixture({ object: { type: 'commit', sha: 'different' } });
  await assert.rejects(check(f.args), /another commit/); assert.equal(f.outputs.publish, 'false');
});
test('annotated tags resolve to the tested commit', async () => {
  const f = fixture({ object: { type: 'tag', sha: 'annotation' }, annotated: { type: 'commit', sha: 'tested' } });
  await check(f.args); assert.equal(f.outputs.publish, 'true');
});
test('API permission errors stop publication', async () => {
  const f = fixture({ error: Object.assign(new Error('Forbidden'), { status: 403 }) });
  await assert.rejects(check(f.args), /Forbidden/); assert.equal(f.outputs.publish, 'false');
});
test('invalid versions are rejected', async () => {
  const f = fixture(); f.args.version = '../main';
  await assert.rejects(check(f.args), /Invalid app version/);
});
