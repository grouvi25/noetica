/// Single source of truth for the Noetica backend URL.
///
/// Override at build time:
///   flutter build apk --dart-define=NOETICA_BACKEND_URL=https://api.example.com
const String kDefaultBackendUrl = String.fromEnvironment(
  'NOETICA_BACKEND_URL',
  defaultValue: 'https://noetica-backend-glglzvme.fly.dev',
);

/// Dev-only bypass for offline/local previews. Production web uses
/// registration-free anonymous sessions instead of this flag.
const bool kDevSkipAuth = String.fromEnvironment(
  'DEV_SKIP_AUTH',
  defaultValue: 'false',
) == 'true';
