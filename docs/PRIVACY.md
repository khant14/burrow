# Burrow privacy policy

_Last updated: November 24, 2026_

Burrow is an SSH client. It is built to collect nothing about you.

## What stays on your device

- **Hosts, snippets and settings** are saved in the app's own storage on your device.
- **Private keys** you paste or import are kept in the system keychain (Keychain on Apple devices) and never leave the device.
- **Passwords** are asked for when you open a connection, held in memory for that session, and never written to disk.

## Network connections

Burrow connects only to the servers you add, using SSH. To show whether a server is up, it opens a plain TCP connection to that server's SSH port every so often. These connections go straight from your device to your server. On iOS, connecting to a server on your own network needs the Local Network permission, which Burrow asks for the first time.

## What Burrow does not do

- No analytics, crash reporting, advertising or tracking.
- No accounts are needed to use the app.
- No data is sold or shared with anyone.

## Optional sync

Sync is off unless you turn it on in Settings, and Burrow works fully without it. It talks only to a sync server you choose, usually one you run yourself. Before anything is uploaded, hosts are encrypted on your device with a key derived from your sync password, so the server stores only ciphertext plus your email, item counts and timestamps. Your password never leaves the device. Private keys and passwords are not synced.

Signing out stops syncing and keeps your hosts on the device. **Delete account** in Settings permanently deletes the account and everything stored with it on the server; hosts on your devices are kept. Anyone running a sync server is responsible for that server.

## Contact

Questions or requests: open an issue at https://github.com/khant14/burrow/issues.
