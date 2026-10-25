# Privacy

Simplex Wing connects directly to panels you configure and their panel-issued Wings/storage URLs. It has no app-operated account service, analytics SDK, advertising SDK, marketplace API or cloud relay.

## Stored on your device

- Panel names, URLs and workspace preferences in app storage.
- Client API keys in the iOS keychain with device-only access.
- Transfer history, downloaded files and temporary working copies.
- Optional widget credentials and snapshots in protected shared app storage or shared keychain when the signing identity permits it.
- Optional player command templates and local command history.

Enable Face ID/passcode protection in Settings to lock the app. Widget data is separately opted in and can be visible while the device is locked. A manual widget data code contains display data without credentials.

## Network access

Your panel receives API requests, console commands and changes you submit. Wings receives its scoped console token, not your panel API key. Signed storage URLs may point to a provider's external object storage. Those providers' privacy practices apply. Explicitly opening documentation links uses your browser. Files downloaded via URL are fetched by your server, as directed by you.

## Removal

Remove a panel in Settings to delete its app key and widget records. Manage downloaded files and transfer history in Transfers. Deleting the app removes its sandbox; iOS can retain keychain items under its own rules. Revoke keys in the panel to invalidate access regardless of device state.

Never include keys, signed URLs, database passwords or personal console output in public issues. Review exports and screenshots before sharing.
