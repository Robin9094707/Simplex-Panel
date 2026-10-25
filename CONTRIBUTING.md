# Contributing

Keep the community edition focused on the standard Pterodactyl Client API, a native iOS experience and English/German parity.

Before a pull request:

1. Run `python3 scripts/validate.py` and regenerate with XcodeGen.
2. Exercise the changed feature on the simulator or a disposable test server as appropriate.
3. Add focused regression coverage for API boundaries, archive parsing or data integrity when behavior changes.
4. Include both language strings in `Shared/German.json`; use `W("English text")` for app-owned UI strings. Preserve interpolation placeholders.
5. Update documentation for user-facing behavior and disclose what remains untested.

Do not commit credentials, signing material, server exports, real player data, generated build folders or Xcode user state. Provider-only integrations and marketplace APIs are outside this repository's scope. Do not modify the separate private-edition repository as part of a community contribution.

The code uses Swift 5 language mode and iOS 26 APIs. XcodeGen's `project.yml` is the project source of truth. Generated `.xcodeproj` files are not checked in.
