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

## Optional sync (not yet in the app)

Burrow's sync server is self-hosted. When sync ships, your vault is encrypted on your device before upload, and the server only stores ciphertext. Anyone running a sync server is responsible for that server. You will be able to delete your sync account, and everything stored with it, from inside the app.

## Contact

Questions or requests: open an issue at https://github.com/khant14/burrow/issues.
