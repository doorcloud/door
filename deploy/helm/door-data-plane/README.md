# door-agent (door-data-plane)

Helm chart for the Door dataplane on Kubernetes:

- Door agent
- Contour / Envoy APIM gateway (`door-apigateway`)
- Optional APIM / CD / CI / onboard / helm-operator / monitoring components

**Chart name:** `door-agent` (see `Chart.yaml`)  
**Version:** see `Chart.yaml` `version`

## Default backend (APIM)

When `doorApiGateway.defaultBackend.enabled` is true (and the external gateway
type is `loadBalancer` or `hostPort`), the chart deploys:

- `Deployment` / `Service` `door-apim-default-backend` in `door-apigateway`
- Catch-all `HTTPRoute` on `Gateway/door` listeners `http` and `https`

Unmatched traffic gets a branded Door APIM page, and the HTTPS listener stays
programmed in Envoy.

Image: `docker.io/doorcloud/door-apim-default-backend` (immutable tags only).

## Values of interest

```yaml
global:
  doorAPI:
    externalUrl: https://api.example.com   # required — your Door API URL

doorApiGateway:
  external:
    type: loadBalancer
    # loadBalancerIP: "…"
  defaultBackend:
    enabled: true
    image:
      repository: docker.io/doorcloud/door-apim-default-backend
      tag: "v.0.0.<sha>"   # never :latest
```

Provide licence material and Kafka brokers via values (do not commit real
secrets). See [`values.yaml`](./values.yaml) and [`../../README.md`](../../README.md).
