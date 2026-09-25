// Published versions are immutable. A draft may be retried only at the same commit.
module.exports = async function ({ github, context, core, version }) {
  if (!/^\d+\.\d+(?:\.\d+)?$/.test(version)) throw new Error('Invalid app version');
  const tag = `v${version}`;
  const repo = context.repo;
  core.setOutput('publish', 'false');
  let release;
  try {
    release = (await github.rest.repos.getReleaseByTag({ ...repo, tag })).data;
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  if (release && !release.draft) {
    core.info(`${tag} is already published; leaving it unchanged.`);
    return;
  }
  let object;
  try {
    object = (await github.rest.git.getRef({ ...repo, ref: `tags/${tag}` })).data.object;
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  // Peel annotated tags before comparing with the exact commit that was tested.
  while (object && object.type === 'tag') {
    object = (await github.rest.git.getTag({ ...repo, tag_sha: object.sha })).data.object;
  }
  if (object && (object.type !== 'commit' || object.sha !== context.sha)) {
    throw new Error(`${tag} points to another commit. Increase the app version before publishing.`);
  }
  core.setOutput('publish', 'true');
};
