# docker-sandbox

## Setup

Allow `sbx` to fetch kits from your GitHub org (e.g. the kit this repo's
`sbx-env/sbxenv.yaml` pulls from `github.com/your-org/docker-sandbox`):

```
sbx settings set kit.allowedSources '["github.com/your-org/"]'
```
