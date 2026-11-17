# key

Stores API keys in the macOS login keychain. Reading, replacing or deleting one requires Touch ID, or the login password when Touch ID is unavailable.

```sh
key set OPENAI_API_KEY        # prompts without echo; or: pbpaste | key set OPENAI_API_KEY
getkey OPENAI_API_KEY         # Touch ID, then prints the key (same as: key get)
key ls                        # names only, no auth
key rm OPENAI_API_KEY
key adopt anthropic           # move a key stored by the old zsh function
```

It also makes SSH keys in the Mac's Secure Enclave, so each SSH connection needs Touch ID:

```sh
key ssh new                   # make a key labelled "default"; Touch ID
key ssh new work              # make another key labelled "work"
key ssh ls                    # labels, fingerprints and handle files, no auth
key ssh rm work               # Touch ID, then delete the key
key ssh add me@example.org    # move a host from its password to the default key
key ssh password example.org  # log in with the password instead of the key
```

Install: `make install` (into `~/.local/bin`, plus a `getkey` symlink). Run the tests with `make test`, which needs Xcode.

## SSH keys

The private key is made inside the Secure Enclave and cannot leave it. Each signature, and so each connection, needs Touch ID. `key ssh new` saves 2 files in `~/.ssh`: the public key, and a handle file named `id_ecdsa_sk_rk_LABEL` that tells OpenSSH which Secure Enclave key to ask for. Neither file is secret.

This uses the tools macOS 26 and later ship: `sc_auth` makes and deletes the key, and OpenSSH reaches it through `/usr/lib/ssh-keychain.dylib`.

### Moving a host to the key

`key ssh add [USER@]HOST [--port N] [--key LABEL]` does 4 things:

1. Makes the `default` key if it does not exist yet. `--key` picks another existing key.
2. Runs `ssh-copy-id`, which asks for the host's password one last time and adds the public key to the server's `~/.ssh/authorized_keys`.
3. Writes a `Host` block to `~/.ssh/config.d/key-cli`. The first time, it backs up `~/.ssh/config` to `~/.ssh/config.key-cli-backup` and adds `Include config.d/key-cli` before the first `Host` or `Match` line, so the blocks apply to every host and win over a later `Host *`.
4. Logs in with the key alone, after Touch ID. If that fails, it removes the `Host` block again. The key stays in the server's `authorized_keys`.

It leaves alone any host whose user, port or key your own `~/.ssh/config` already sets, and lists those settings instead. The server needs OpenSSH 8.2 or later to accept these keys.

### Logging in with the password

`key ssh add` does not turn off password login on the server, so the password keeps working. `ssh HOST` tries the key first. `key ssh password HOST` runs ssh with key login turned off, so the host asks for its password. Arguments after the host go to ssh as they are. To stop a server accepting passwords, set `PasswordAuthentication no` in its `sshd_config`.

Deleting a key cuts off every server that trusted it, and those servers keep a stale line in `authorized_keys`.

## Why another tool can't bypass it

The keychain item is created by this binary, so its ACL trusts only this binary. Any other process gets the keychain-password dialog, including `security find-generic-password -w`. The Touch ID check lives inside the binary, and the ACL is pinned to its code hash, so a patched copy is a different binary and also gets the dialog.

Keys stored by the old zsh function trust `/usr/bin/security`, so anyone can read them without a prompt. `key adopt` re-creates them under this binary.

## Caveats

- **After a rebuild**, the code hash changes. The first `get` of each key then shows a "key wants to use…" dialog. Enter the login password and choose Always Allow.
- **The protection only holds while your login password is secret.** Someone who knows it can approve the keychain dialog.
- **Each `getkey` asks for Touch ID**, so a script that reads five keys prompts five times.
