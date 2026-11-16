# syntax=docker/dockerfile:1
#
# Deterministic Documentation Toolchain Image
# ============================================
# Contains every tool required to run the deterministic documentation pipeline:
#
#   Terraform             — infrastructure provisioning + plan JSON
#   terraform-docs        — auto-generate Markdown from HCL modules
#   OPA                   — policy evaluation against terraform plan JSON
#   Ansible               — agentless configuration management + Jinja2 templating
#   Python 3              — MkDocs runtime + Ansible dependency
#   MkDocs                — static site generation
#   Material theme        — MkDocs Material for MkDocs theme
#   PowerShell Core 7.4   — DSC resource class execution + DscResource.DocGenerator
#   Pester 5              — DSC resource unit tests
#   DscResource.DocGenerator — auto-generate Markdown from DSC class comment-based help
#   .NET SDK 10 (10.0.404) — application layer build, tests, native OpenAPI + C4Sharp
#   DocFX 2.81.0          — .NET API reference (Markdown export), pinned to match dotnet/dotnet-tools.json
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
ARG DOTNET_VERSION=10.0.404

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

# --- .NET SDK ---
# The dot.net installer script is used instead of the Debian package feed:
# the microsoft-prod apt repository carries a moving SDK version and has had
# signing issues on newer Debian releases. The version here is pinned to the
# same SDK as dotnet/global.json so the container builds exactly what CI and
# the local developer environment build.
RUN curl -fsSL "https://dot.net/v1/dotnet-install.sh" -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 10.0 --version "${DOTNET_VERSION}" --install-dir /usr/share/dotnet \
    && rm /tmp/dotnet-install.sh \
    && /usr/share/dotnet/dotnet --version

# ---------------------------------------------------------------------------
# Stage 2 — final runtime image
# ---------------------------------------------------------------------------
FROM python:3.12-slim

ARG DOTNET_VERSION=10.0.404

# Copy binaries from downloader stage
COPY --from=downloader /usr/local/bin/terraform      /usr/local/bin/terraform
COPY --from=downloader /usr/local/bin/terraform-docs /usr/local/bin/terraform-docs
COPY --from=downloader /usr/local/bin/opa            /usr/local/bin/opa
COPY --from=downloader /usr/share/dotnet              /usr/share/dotnet

# System dependencies — Ansible, MkDocs, PowerShell Core, and the .NET runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-client \
        sshpass \
        iproute2 \
        procps \
        wget \
        apt-transport-https \
        ca-certificates \
        libicu72 \
    # PowerShell Core (Microsoft package repository)
    && wget -qO /tmp/packages-microsoft-prod.deb \
        "https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb" \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y --no-install-recommends powershell \
    && rm -rf /var/lib/apt/lists/* /tmp/packages-microsoft-prod.deb

# Python tooling — pinned for reproducibility
RUN pip install --no-cache-dir \
    "ansible==10.7.0" \
    "mkdocs==1.6.1" \
    "mkdocs-material==9.5.49" \
    "pymdown-extensions==10.13"

# PowerShell modules — Pester + DscResource.DocGenerator + PlatyPS
# Modules are installed to the system-wide module path so all users can use them.
RUN pwsh -NonInteractive -Command "\
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module -Name Pester               -RequiredVersion 5.6.1  -Force -SkipPublisherCheck; \
    Install-Module -Name PlatyPS              -RequiredVersion 2.0.6  -Force; \
    Install-Module -Name DscResource.DocGenerator -RequiredVersion 0.12.2 -Force"

# .NET SDK — expose the SDK copied from the downloader stage.
# DOTNET_ROOT lets the SDK locate its runtime and shared assemblies; PATH
# includes both the SDK and the global-tools directory (`~/.dotnet/tools`),
# where the DocFX shim below is installed.
RUN ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="${PATH}:/usr/share/dotnet:/root/.dotnet/tools"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# DocFX as a pinned .NET global tool (2.81.0, matching dotnet/dotnet-tools.json)
# so `docfx --version` works out of the box; generate-docs.sh additionally
# restores the same version from the local tool manifest before running it.
RUN dotnet --version \
    && dotnet tool install --global docfx --version 2.81.0 \
    && docfx --version

WORKDIR /workspace

# Default command: show tool versions for quick verification
CMD ["/bin/bash", "-c", \
     "echo '=== Tool versions ===' && \
      terraform version && \
      terraform-docs version && \
      opa version && \
      ansible --version | head -1 && \
      mkdocs --version && \
      pwsh --version && \
      pwsh -NonInteractive -Command \"(Get-Module Pester -ListAvailable)[0].Version | ForEach-Object { \\\"Pester \$_\\\" }\" && \
      dotnet --version && \
      docfx --version"]
