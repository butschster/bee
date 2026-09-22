# Bee driver

`bee/driver` is the shared declarative contract for managed harness providers.
Install it with `bee/threads` and one provider component such as
`bee/driver-codex`.

It defines the driver binding, bounded launch and configuration values, protocol
framing, and saved profile preferences. It does not start processes, select an
executable, read credentials, or grant permissions.

A host activates a provider binding and supplies its requirements. Providers
then return launch/configuration data; Bee placement runs the selected program
and the thread service stores its observations.
