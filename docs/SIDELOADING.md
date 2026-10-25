# Signing and sideloading

Release IPAs are unsigned. Use a legitimate signing identity and a tool supporting modern iOS app bundles with embedded extensions. The project does not include a certificate, provisioning profile or private key.

- Main application: `eu.simplexsmp.wing`
- Widget extension: `eu.simplexsmp.wing.widgets`
- App Group: `group.eu.simplexsmp.wing`
- Shared keychain family: `<TeamPrefix>.eu.simplexsmp.wing.shared`
- URL scheme: `simplexwing://`

Sign the application and embedded widget extension consistently. If your signing service rewrites identifiers, retain a matching App Group for both targets. Signing permissions determine whether widgets can access shared data; the app cannot grant entitlements removed by the signer.

Without shared access, Settings offers a data code for a **manual snapshot** widget. It contains selected display data and no API key. It does not automatically update. Widgets can display shared data while the phone is locked; choose servers accordingly.

Live Activities and background URLSession transfers are subject to iOS lifecycle rules. Force quitting can stop transfers. Expired download URLs may require reopening the panel to request a new link. Uploads may need to be selected again.

To update, use the same app identifier and signing identity where possible. Do not delete the installed app without exporting anything you need to retain. This edition has a different identifier from the private Simplex Panel app and does not migrate its credentials.
