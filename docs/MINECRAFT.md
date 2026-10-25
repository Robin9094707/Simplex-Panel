# Minecraft workflows

## Plugins

Open **More → Manage server → Plugins & JAR files**. Versions are read from JAR metadata. Small visible JARs are inspected automatically; larger files are inspected on demand, up to the 128 MiB inspection limit.

For a new plugin, stop the server, choose **Install new plugin** and select a local JAR. Review metadata and compatibility. Installation stages the file and verifies its SHA-256 before moving it into `/plugins`. Existing plugin identity or filenames are not silently overwritten.

For a **Paper update**, choose **Upload update file** on the installed plugin. The app compares identity and version, checks the `bukkit.yml` update folder and pending JARs, then verifies the uploaded file. The running plugin is not hot-reloaded; Paper applies the staged update at the next start. This staged workflow is intended for Paper/Bukkit-compatible update handling. Use the general file manager for other server/plugin ecosystems.

Enable/disable and delete operations require an offline server. Disabling renames `.jar` to `.jar.disabled`; enabling reverses this. Plugin configuration folders are preserved.

## Mods

Stop the server and open **Mods & mod updates**. Select a local JAR matching Minecraft version, loader and dependencies. The app reads common Fabric, Quilt, Forge, NeoForge and legacy Forge metadata. Client-only files are rejected when metadata identifies them. Metadata cannot prove every dependency is installed.

Updates compare mod identity and loader, stage and verify the upload, then move the previous JAR to `/simplex-mod-backups/<transaction>/`. If the final move fails, restoration of the old JAR is attempted. Read any recovery error before starting the server. Unknown metadata requires manual review through Files.

A JAR backup does not back up worlds, databases or configurations. Use a full server backup before major changes.

## Players, TPS and NBT

Player counts/names are read from `list` console output. TPS uses a `tps` command if available, such as on Paper/Purpur. These are console-derived values, not a universal Pterodactyl player API. Unsupported or stale values remain visibly unavailable.

Player actions show the exact command before sending. Live `data get` queries require console access and a compatible Java server. Saved player NBT editing is an offline workflow with an explicit apply step, file conflict checks and a verified backup. Bedrock LevelDB and region editing are not supported.
