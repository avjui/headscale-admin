# Local Docker test environment

Runs headscale-admin (built from the repository `Dockerfile`, same image as CI)
against a real headscale, both behind one Caddy proxy so UI and API share an origin.

```
./hs-test.sh up        # build + start, creates API key and users alice/bob
./hs-test.sh smoke     # API checks (exit code 1 on failure)
./hs-test.sh clients   # two tailscale clients waiting for registration
./hs-test.sh down      # remove everything (containers, volumes, images, state)
```

Open http://localhost:8081/admin/ and enter API URL `http://localhost:8081` and the
key printed by `up` (also `./hs-test.sh key`).

| Command | |
|---|---|
| `up` | build headscale-admin image, start headscale + proxy, print URL and API key |
| `rebuild` | rebuild only the headscale-admin image after code changes |
| `smoke` | API checks: endpoints, tagged pre-auth key, policy with SSH `check`, 0.29 auth endpoints; with a waiting `client2` also registration and disable expiry. **Overwrites the test policy.** |
| `clients` / `urls` | start `client1`/`client2`, print their register URLs for Nodes → + → Register / Approve / Reject |
| `status`, `key`, `logs [svc]` | containers, URL and key, follow logs |
| `hs <args>` | headscale CLI, e.g. `./hs-test.sh hs nodes list` |
| `down` (alias `reset`) | stop and delete everything: containers, volumes, network, the images used (headscale, caddy, tailscale, headscale-admin) and `.state`. The next `up` pulls and builds again. |

Other headscale version or port:

```
HEADSCALE_VERSION=0.28.0 HS_TEST_PORT=8090 ./hs-test.sh up
```

The headscale config is `headscale/config.yaml.tmpl` (policy mode `database`,
`node.expiry: 0`); the rendered config, API key and nothing else lives in `.state/`.
