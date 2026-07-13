# Door dataplane

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
