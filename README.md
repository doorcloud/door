# Door distribution

Public distribution channel for Door: the `doorctl` CLI and the `door-agent`
Helm chart both ship from this repository.

## Install the `doorctl` CLI

`doorctl` manages your Door clusters, projects, and environments from the
terminal. Pick the channel that fits your platform:

| Channel | Command |
|---|---|
| **Homebrew** (macOS / Linux) | `brew install doorcloud/door/doorctl` |
| **Install script** (macOS / Linux) | `curl -sSL https://raw.githubusercontent.com/doorcloud/door/main/scripts/doorctl.sh \| sh -s` |
| **Direct download** | Grab the archive for your OS/arch from the [latest release](https://github.com/doorcloud/door/releases/latest) |

The install script detects your processor, verifies release checksums, and
installs without `sudo` when a user-writable directory is available (falling
back to `~/.local/bin`). Pin a specific version by passing it as an argument:
`... | sh -s -- v2.6.0`.

After installing, connect the CLI to your console:

```bash
doorctl config --server-url <YOUR_DOOR_URL> --organization <YOUR_ORG>
doorctl login --token <YOUR_CLI_TOKEN> --organization <YOUR_ORG>
doorctl version
```

> **Migrating from the old channels?** The legacy `beopencloud/cno` tap, release
> feed, and install script are **deprecated**. They still work and now redirect
> to this channel, but please update your scripts to the commands above. If you
> installed from the old tap, run `brew uninstall doorctl && brew untap
> beopencloud/cno` before `brew install doorcloud/door/doorctl`.

## Door dataplane Helm chart (`door-agent`)

Public Helm chart for the Door dataplane (`door-agent`).

## Layout

```
README.md
deploy/
  README.md
  helm/
    door-data-plane/     # chart name: door-agent
docs/
  index.yaml             # Helm repository index
  door-agent-v*.tgz      # packaged chart versions
```

## Chart

| Field | Value |
|-------|--------|
| Chart name | `door-agent` |
| Directory | `deploy/helm/door-data-plane` |
| Current version | see `Chart.yaml` |

The chart installs Contour/Envoy (Door APIM gateway), optional operators, and a
branded **default backend** catch-all so the HTTPS listener always has an
attached route.

## Install

```bash
helm repo add door https://raw.githubusercontent.com/doorcloud/door/main/docs
helm repo update
helm search repo door/door-agent --versions
helm install door door/door-agent -n door-system --create-namespace
```

Override required values (API URL, Kafka, licence, images) via a values file —
see `deploy/helm/door-data-plane/values.yaml` for the schema.

## Build & package

```bash
cd deploy/helm/door-data-plane
helm dependency update
helm package .
mv door-agent-*.tgz ../../../docs/
cd ../../../docs
helm repo index . --url https://raw.githubusercontent.com/doorcloud/door/main/docs --merge index.yaml
```

## License

See repository license / Door product terms.
