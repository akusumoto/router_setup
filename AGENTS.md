# Router access

- Connect to the OpenWrt router as `root` at `192.168.1.1` using `.local-ssh/id_ed25519_v2`.
- For a series of router commands, open one persistent SSH session and run the commands through that session. Reconnect only if the session ends or becomes unusable.
- A single, isolated command may use a one-off SSH connection.
