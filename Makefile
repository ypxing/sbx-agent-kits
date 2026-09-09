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

# ── Agent image references (used by gen-specs) ───────────────────────────────
SBX_PI_IMAGE      ?= $(REPO):pi-docker-bedrock
SBX_CLAUDE_IMAGE  ?= $(REPO):claude-docker-bedrock
SBX_CODEX_IMAGE   ?= $(REPO):codex-docker-bedrock
SBX_COPILOT_IMAGE ?= $(REPO):copilot-docker

export SBX_PI_IMAGE SBX_CLAUDE_IMAGE SBX_CODEX_IMAGE SBX_COPILOT_IMAGE

IMAGES := claude-docker-bedrock copilot-docker pi-docker-bedrock

.PHONY: all $(IMAGES) \
        tag tag-claude-docker-bedrock tag-copilot-docker tag-pi-docker-bedrock \
        push push-claude-docker-bedrock push-copilot-docker push-pi-docker-bedrock \
        ecr-login gen-specs

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

## sbx-agent:claude-docker-bedrock
claude-docker-bedrock:
	docker buildx bake claude-docker-bedrock

## sbx-agent:copilot-docker
copilot-docker:
	docker buildx bake copilot-docker

## sbx-agent:pi-docker-bedrock
pi-docker-bedrock:
	docker buildx bake pi-docker-bedrock

# ── ECR login ────────────────────────────────────────────────────────────────

## Authenticate Docker to ECR
ecr-login:
	$(AWS_SSO_EXPORT) \
	aws ecr get-login-password --region $(SSO_REGION) \
	  | docker login --username AWS --password-stdin $(ECR)

# ── Tag ──────────────────────────────────────────────────────────────────────

## Tag all three images for ECR
tag: tag-claude-docker-bedrock tag-copilot-docker tag-pi-docker-bedrock

tag-claude-docker-bedrock:
	docker tag sbx-agent:claude-docker-bedrock $(REPO):claude-docker-bedrock

tag-copilot-docker:
	docker tag sbx-agent:copilot-docker $(REPO):copilot-docker

tag-pi-docker-bedrock:
	docker tag sbx-agent:pi-docker-bedrock $(REPO):pi-docker-bedrock

# ── Push ─────────────────────────────────────────────────────────────────────

## Push all three images to ECR
push: push-claude-docker-bedrock push-copilot-docker push-pi-docker-bedrock

push-claude-docker-bedrock:
	docker push $(REPO):claude-docker-bedrock

push-copilot-docker:
	docker push $(REPO):copilot-docker

push-pi-docker-bedrock:
	docker push $(REPO):pi-docker-bedrock

# ── Combined workflows ───────────────────────────────────────────────────────

## Build → tag → push everything  (requires ECR login first)
_release: all tag push
release: ecr-login _release

## Build → tag → push a single image, e.g.: make release-image IMAGE=copilot-docker
release-image: ecr-login
	docker buildx bake $(IMAGE)
	docker tag  sbx-agent:$(IMAGE) $(REPO):$(IMAGE)
	docker push $(REPO):$(IMAGE)

# ── Generate agent specs ─────────────────────────────────────────────────────

## Render agents/*/spec.yaml from *.tpl using ECR image references
gen-specs:
	bash scripts/gen-specs.sh
