# Door data-plane Helm charts

| Directory | Published chart name | Purpose |
|-----------|----------------------|---------|
| [`door-data-plane/`](./helm/door-data-plane/) | `door-agent` | Door agent, Contour/Envoy APIM gateway, optional operators |

## Build

```bash
cd deploy/helm/door-data-plane
helm dependency update
helm package .
# → door-agent-v<version>.tgz
```

## Packaged versions

Helm index under `docs/` on `main`:

```bash
helm repo add door https://raw.githubusercontent.com/doorcloud/door/main/docs
helm repo update
helm pull door/door-agent --version v3.0.16
```

## OCI (optional)

```bash
helm push door-agent-<version>.tgz oci://ghcr.io/doorcloud/charts
```

## Notes

- Chart **name** is `door-agent`; directory name is `door-data-plane`.
- Pin `doorApiGateway.defaultBackend.image.tag` to an immutable tag (never `:latest`).
