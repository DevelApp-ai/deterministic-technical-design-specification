# syntax=docker/dockerfile:1
#
# Deterministic Documentation Toolchain Image
# ============================================
# Contains every tool required to run the deterministic documentation pipeline:
#
#   Terraform      — infrastructure provisioning + plan JSON
#   terraform-docs — auto-generate Markdown from HCL modules
#   OPA            — policy evaluation against terraform plan JSON
#   Ansible        — agentless configuration management + Jinja2 templating
#   Python 3       — MkDocs runtime + Ansible dependency
#   MkDocs         — static site generation
#   Material theme — MkDocs Material for MkDocs theme
#
# Build:  docker build -t dtds-example .
# Run:    docker run --rm -v "$(pwd)":/workspace dtds-example \
#             scripts/generate-docs.sh

# ---------------------------------------------------------------------------
# Stage 1 — download binary tools
# ---------------------------------------------------------------------------
FROM debian:12-slim AS downloader

ARG TERRAFORM_VERSION=1.9.8
ARG TERRAFORM_DOCS_VERSION=0.19.0
ARG OPA_VERSION=0.69.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# --- Terraform ---
RUN curl -fsSL \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/terraform \
    && rm /tmp/terraform.zip

# --- terraform-docs ---
RUN curl -fsSL \
    "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-amd64.tar.gz" \
    -o /tmp/terraform-docs.tar.gz \
    && tar -xzf /tmp/terraform-docs.tar.gz -C /usr/local/bin/ terraform-docs \
    && chmod +x /usr/local/bin/terraform-docs \
    && rm /tmp/terraform-docs.tar.gz

# --- OPA ---
RUN curl -fsSL \
    "https://github.com/open-policy-agent/opa/releases/download/v${OPA_VERSION}/opa_linux_amd64_static" \
    -o /usr/local/bin/opa \
    && chmod +x /usr/local/bin/opa

# ---------------------------------------------------------------------------
# Stage 2 — final runtime image
# ---------------------------------------------------------------------------
FROM python:3.12-slim

# Copy binaries from downloader stage
COPY --from=downloader /usr/local/bin/terraform      /usr/local/bin/terraform
COPY --from=downloader /usr/local/bin/terraform-docs /usr/local/bin/terraform-docs
COPY --from=downloader /usr/local/bin/opa            /usr/local/bin/opa

# System dependencies required by Ansible and MkDocs
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-client \
        sshpass \
        iproute2 \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Python tooling — pinned for reproducibility
RUN pip install --no-cache-dir \
    "ansible==10.7.0" \
    "mkdocs==1.6.1" \
    "mkdocs-material==9.5.49" \
    "pymdown-extensions==10.13"

WORKDIR /workspace

# Default command: show tool versions for quick verification
CMD ["/bin/bash", "-c", \
     "echo '=== Tool versions ===' && \
      terraform version && \
      terraform-docs version && \
      opa version && \
      ansible --version | head -1 && \
      mkdocs --version"]
