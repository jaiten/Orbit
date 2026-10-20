"""Prepare a manual-signing XcodeGen spec on an ephemeral macOS CI runner."""
import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

import yaml

TEAM = '5T6K789X4T'
GROUP = 'group.com.jaiten.orbit.shared'


def validate_profile(profile, bundle):
    entitlements = profile['Entitlements']
    if profile.get('TeamIdentifier') != [TEAM]:
        raise ValueError('Provisioning profile belongs to a different team')
    if entitlements.get('application-identifier') != f'{TEAM}.{bundle}':
        raise ValueError(f'Provisioning profile does not match {bundle}')
    if GROUP not in entitlements.get('com.apple.security.application-groups', []):
        raise ValueError(f'Provisioning profile for {bundle} is missing the shared App Group')
    if (profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices')
            or entitlements.get('get-task-allow')):
        raise ValueError('Use an App Store Connect distribution profile')
    if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError('Provisioning profile has expired')


def main():
    root = Path(__file__).resolve().parents[1]
    spec = yaml.safe_load((root / 'ios/project.yml').read_text())
    # Monotonic for this workflow, including manual retries; exceeds prototype build 2.
    spec['settings']['base']['CURRENT_PROJECT_VERSION'] = str(
        1000 + int(os.environ['GITHUB_RUN_NUMBER']) * 100 + int(os.environ['GITHUB_RUN_ATTEMPT']))
    profiles = {}
    profile_dir = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
    profile_dir.mkdir(parents=True, exist_ok=True)
    signed = [
        ('Orbit', 'com.jaiten.orbit', 'APP_PROFILE_BASE64', 'orbit-app'),
        ('OrbitWidgets', 'com.jaiten.orbit.widgets', 'WIDGET_PROFILE_BASE64', 'orbit-widget'),
    ]
    # The share extension ships once its profile is configured (docs/testflight.md);
    # until then the build leaves it out instead of failing.
    if os.environ.get('SHARE_PROFILE_BASE64'):
        signed.append(('OrbitShare', 'com.jaiten.orbit.share', 'SHARE_PROFILE_BASE64', 'orbit-share'))
    else:
        spec['targets'].pop('OrbitShare', None)
        app = spec['targets']['Orbit']
        app['dependencies'] = [d for d in app.get('dependencies', []) if d.get('target') != 'OrbitShare']
        print('SHARE_PROFILE_BASE64 is not set; building without the share extension.')
    for target, bundle, secret, filename in signed:
        path = profile_dir / f'{filename}.mobileprovision'
        path.write_bytes(base64.b64decode(os.environ[secret]))
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)]))
        validate_profile(profile, bundle)
        profiles[bundle] = profile['UUID']
        spec['targets'][target]['settings']['base'].update({
            'CODE_SIGN_STYLE': 'Manual', 'CODE_SIGN_IDENTITY': 'Apple Distribution',
            'DEVELOPMENT_TEAM': TEAM, 'PROVISIONING_PROFILE_SPECIFIER': profile['UUID'],
        })
    (root / 'ios/signing-project.json').write_text(json.dumps(spec, indent=2))
    options = {
        'method': 'app-store-connect', 'destination': 'export', 'teamID': TEAM,
        'signingStyle': 'manual', 'signingCertificate': 'Apple Distribution',
        'provisioningProfiles': profiles, 'manageAppVersionAndBuildNumber': False,
        'uploadSymbols': True,
    }
    (Path(os.environ['RUNNER_TEMP']) / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
    key_id = os.environ['ASC_KEY_ID']
    if not re.fullmatch(r'[A-Za-z0-9]+', key_id):
        raise ValueError('Invalid App Store Connect key ID')
    key_dir = Path.home() / '.appstoreconnect/private_keys'
    key_dir.mkdir(parents=True, exist_ok=True)
    key_path = key_dir / f'AuthKey_{key_id}.p8'
    key_path.write_text(os.environ['ASC_PRIVATE_KEY'])
    key_path.chmod(0o600)
    print(f'Validated {len(signed)} profiles and prepared signed build configuration.')


if __name__ == '__main__':
    main()
