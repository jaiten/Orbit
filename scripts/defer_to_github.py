"""Codemagic's first step: leave the build to GitHub Actions when GitHub can run it.

GitHub is the main iOS pipeline (.github/workflows/ios.yml, then testflight.yml). Codemagic starts on the same
pushes and asks GitHub whether its iOS run for this commit got a runner. If it did, GitHub has it and Codemagic
stops. If GitHub cancels the run before it starts (as it does when Actions minutes run out), or no runner picks
it up in time, Codemagic cancels GitHub's queued run, so the two never both upload, and builds itself.

Writes SKIP_BUILD=1 to $CM_ENV when GitHub has the build; later steps check it. FORCE_BUILD=true skips the check.
Needs GITHUB_TOKEN: a fine-grained token for jaiten/Orbit with Actions read and write.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPO = 'jaiten/Orbit'
WORKFLOW = 'ios.yml'
WAIT_SECONDS = 6 * 60      # a runner normally takes a minute or two when minutes are available
NO_RUN_SECONDS = 2 * 60    # GitHub creates the run within seconds of the push
POLL_SECONDS = 20


def decide(run, jobs, waited):
    """'github' when GitHub has the build, 'here' when Codemagic should build, 'wait' to ask again.

    `run` is GitHub's iOS run for this commit (or None), `jobs` its jobs, `waited` seconds so far.
    """
    if run is None:
        return 'here' if waited >= NO_RUN_SECONDS else 'wait'
    started = any(job.get('runner_name') or job.get('steps') for job in jobs)
    if started:
        return 'github'
    if run.get('status') == 'completed':
        return 'here'  # finished without ever getting a runner: cancelled or blocked
    return 'here' if waited >= WAIT_SECONDS else 'wait'


def api(path, token, method='GET'):
    request = urllib.request.Request(
        f'https://api.github.com/repos/{REPO}/{path}', method=method,
        headers={'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json',
                 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'orbit-codemagic'})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body else {}


def skip(reason):
    print(reason)
    with open(os.environ['CM_ENV'], 'a') as env:
        env.write('SKIP_BUILD=1\n')


def main():
    commit = os.environ['CM_COMMIT']
    message = subprocess.run(['git', 'log', '-1', '--format=%B', commit], capture_output=True, text=True).stdout
    if '[skip testflight]' in message:
        return skip('The commit says [skip testflight]; nothing to upload.')
    if os.environ.get('FORCE_BUILD') == 'true':
        return print('FORCE_BUILD is set: building here without asking GitHub.')
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        return print('No GITHUB_TOKEN: building here (GitHub cannot be asked).')
    waited = 0
    while True:
        try:
            runs = api(f'actions/workflows/{WORKFLOW}/runs?head_sha={commit}&event=push&per_page=5', token)
            run = (runs.get('workflow_runs') or [None])[0]
            jobs = api(f'actions/runs/{run["id"]}/jobs', token).get('jobs', []) if run else []
        except (urllib.error.URLError, KeyError, ValueError) as error:
            print(f'Could not ask GitHub ({error}); building here.')
            return
        verdict = decide(run, jobs, waited)
        if verdict == 'github':
            return skip(f'GitHub is building this commit: {run["html_url"]}. Nothing to do here.')
        if verdict == 'here':
            if run and run.get('status') != 'completed':
                try:
                    api(f'actions/runs/{run["id"]}/cancel', token, method='POST')
                    print('Cancelled GitHub\'s queued run so only this build uploads.')
                except urllib.error.URLError as error:
                    print(f'Could not cancel GitHub\'s run ({error}); it has not started, building here anyway.')
            print('GitHub could not run this build (no runner or no minutes): building on Codemagic.')
            return
        print(f'GitHub\'s run is still waiting for a runner ({waited // 60} min); asking again shortly.')
        time.sleep(POLL_SECONDS)
        waited += POLL_SECONDS


if __name__ == '__main__':
    sys.exit(main())
