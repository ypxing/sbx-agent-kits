# ── AWS SSO / build config ───────────────────────────────────────────────────
# Override any of these via environment variables or a local .env file.
# Example:
#   export SSO_START_URL=https://myorg.awsapps.com/start
#   export SSO_ACCOUNT_ID=123456789012
#   export SSO_REGION=ap-southeast-2
#   export SSO_ROLE_NAME=MyRole
SSO_START_URL       ?= https://YOUR_ORG.awsapps.com/start
SSO_REGION          ?= ap-southeast-2
SSO_ROLE_NAME       ?= MyRole
SSO_ACCOUNT_ID      ?= 123456789012
INSTALL_CODING_CREW ?= false

AWS_PROFILE ?= sso-live

# Exports the SSO-derived credentials for $(AWS_PROFILE) into the current
# recipe's shell; used wherever an `aws` call needs them (ecr-login,
# sbx-pull-secret).
AWS_SSO_EXPORT = eval "$$(aws configure export-credentials --profile $(AWS_PROFILE) --format env)";

export SSO_START_URL SSO_REGION SSO_ROLE_NAME SSO_ACCOUNT_ID INSTALL_CODING_CREW

# ── ECR ───────────────────────────────────────────────────────────────────────
ECR  ?= $(SSO_ACCOUNT_ID).dkr.ecr.$(SSO_REGION).amazonaws.com
REPO := $(ECR)/sbx-agent

# ── Docker Hub (public) ────────────────────────────────────────────────────────
# No AWS credentials or Bedrock routing config are baked into any image
# (both are applied at sandbox-creation time via kits/mixins/aws/), so every
# image built here is safe to publish publicly.
DOCKERHUB_USER ?= your-dockerhub-username
PUBLIC_REPO    := docker.io/$(DOCKERHUB_USER)/sbx-agent

export DOCKERHUB_USER

IMAGES        := claude-docker copilot-docker pi-docker
PUBLIC_IMAGES := claude-docker codex-docker copilot-docker pi-docker

.PHONY: all $(IMAGES) all-public \
        tag tag-claude-docker tag-copilot-docker tag-pi-docker \
        push push-claude-docker push-copilot-docker push-pi-docker \
        ecr-login docker-login \
        tag-public tag-public-claude-docker tag-public-codex-docker tag-public-copilot-docker tag-public-pi-docker \
        push-public push-public-claude-docker push-public-codex-docker push-public-copilot-docker push-public-pi-docker \
        publish publish-image

# -- AWS SSO login (optional) ------------------------------------------------------
## Log in to AWS SSO and set up credentials for the current shell session.
## This is optional; you can also log in manually with `aws sso login`.
sso-login:
	aws sso login --profile $(AWS_PROFILE)

sbx-pull-secret: sso-login
	$(AWS_SSO_EXPORT) \
	aws ecr get-login-password --region $(SSO_REGION) | sbx secret set --force --registry $(SSO_ACCOUNT_ID).dkr.ecr.$(SSO_REGION).amazonaws.com --username AWS --password-stdin

# ── Build ────────────────────────────────────────────────────────────────────

## Build all three images
all: $(IMAGES)

## sbx-agent:copilot-docker
copilot-docker:
	docker buildx bake copilot-docker

## Build all four images for public release
all-public: $(PUBLIC_IMAGES)

## sbx-agent:claude-docker
claude-docker:
	docker buildx bake claude-docker

## sbx-agent:codex-docker
codex-docker:
	docker buildx bake codex-docker

## sbx-agent:pi-docker
pi-docker:
	docker buildx bake pi-docker

# ── ECR login ────────────────────────────────────────────────────────────────

## Authenticate Docker to ECR
ecr-login:
	$(AWS_SSO_EXPORT) \
	aws ecr get-login-password --region $(SSO_REGION) \
	  | docker login --username AWS --password-stdin $(ECR)

# ── Docker Hub login ─────────────────────────────────────────────────────────

## Authenticate Docker to Docker Hub. Set DOCKERHUB_TOKEN to log in
## non-interactively (e.g. in CI); otherwise you'll be prompted for a password.
docker-login:
	@if [ -n "$$DOCKERHUB_TOKEN" ]; then \
	  echo "$$DOCKERHUB_TOKEN" | docker login --username $(DOCKERHUB_USER) --password-stdin; \
	else \
	  docker login --username $(DOCKERHUB_USER); \
	fi

# ── Tag ──────────────────────────────────────────────────────────────────────

## Tag all three images for ECR
tag: tag-claude-docker tag-copilot-docker tag-pi-docker

tag-claude-docker:
	docker tag sbx-agent:claude-docker $(REPO):claude-docker

tag-copilot-docker:
	docker tag sbx-agent:copilot-docker $(REPO):copilot-docker

tag-pi-docker:
	docker tag sbx-agent:pi-docker $(REPO):pi-docker

# ── Push ─────────────────────────────────────────────────────────────────────

## Push all three images to ECR
push: push-claude-docker push-copilot-docker push-pi-docker

push-claude-docker:
	docker push $(REPO):claude-docker

push-copilot-docker:
	docker push $(REPO):copilot-docker

push-pi-docker:
	docker push $(REPO):pi-docker

# ── Tag (public) ─────────────────────────────────────────────────────────────

## Tag all four images for Docker Hub
tag-public: tag-public-claude-docker tag-public-codex-docker tag-public-copilot-docker tag-public-pi-docker

tag-public-claude-docker:
	docker tag sbx-agent:claude-docker $(PUBLIC_REPO):claude-docker

tag-public-codex-docker:
	docker tag sbx-agent:codex-docker $(PUBLIC_REPO):codex-docker

tag-public-copilot-docker:
	docker tag sbx-agent:copilot-docker $(PUBLIC_REPO):copilot-docker

tag-public-pi-docker:
	docker tag sbx-agent:pi-docker $(PUBLIC_REPO):pi-docker

# ── Push (public) ────────────────────────────────────────────────────────────

## Push all four images to Docker Hub
push-public: push-public-claude-docker push-public-codex-docker push-public-copilot-docker push-public-pi-docker

push-public-claude-docker:
	docker push $(PUBLIC_REPO):claude-docker

push-public-codex-docker:
	docker push $(PUBLIC_REPO):codex-docker

push-public-copilot-docker:
	docker push $(PUBLIC_REPO):copilot-docker

push-public-pi-docker:
	docker push $(PUBLIC_REPO):pi-docker

# ── Combined workflows ───────────────────────────────────────────────────────

## Build → tag → push everything  (requires ECR login first)
_release: all tag push
release: ecr-login _release

## Build → tag → push a single image, e.g.: make release-image IMAGE=copilot-docker
release-image: ecr-login
	docker buildx bake $(IMAGE)
	docker tag  sbx-agent:$(IMAGE) $(REPO):$(IMAGE)
	docker push $(REPO):$(IMAGE)

## Build → tag → push all four images to Docker Hub.
## Run `make docker-login` (or `docker login`) once beforehand — not a
## prerequisite here since Docker Hub sessions persist, unlike ECR's
## short-lived SSO tokens above.
publish: all-public tag-public push-public

## Build → tag → push a single image to Docker Hub, e.g.: make publish-image IMAGE=claude-docker
publish-image:
	docker buildx bake $(IMAGE)
	docker tag  sbx-agent:$(IMAGE) $(PUBLIC_REPO):$(IMAGE)
	docker push $(PUBLIC_REPO):$(IMAGE)
