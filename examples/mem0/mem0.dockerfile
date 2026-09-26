# syntax=docker/dockerfile:1
#
# mem0 is an env-carrying overlay. It installs nothing into the image: the
# mem0ai wheel and the spaCy model land in the *composed base's* system Python
# at create time, via the lifecycle install hooks in mem0.yaml (a mixin overlay
# lands on an unknown base, so relocating site-packages here would not resolve).
#
# This recipe exists only to carry the runtime environment onto the composed
# image. v1 `environment.variables` becomes ENV, which is one of the additive
# image-config fields that merge at assembly — so a mixin's ENV *does* reach the
# composed image (only the contract fields entrypoint/cmd/user/workdir, which
# the workload anchors, are ignored). ENV must be on the recipe's final stage.
#
# `FROM scratch` keeps the layer purely the overlay: the frontend stages the
# descriptor as the single content layer and this ENV rides in the image config.
FROM scratch

# MIGRATION NOTE: NO_PROXY / no_proxy carried verbatim from v1. They let the
# mem0 client reach the host's Docker Model Runner (host.docker.internal:12434)
# directly instead of through the sandbox's forced egress proxy. OPENAI_* point
# the OpenAI-compatible client at the DMR; the api_key is the DMR sentinel "dmr",
# not a real credential — which is why this kit declares no credential@1.
ENV OPENAI_BASE_URL="http://host.docker.internal:12434/engines/v1" \
    OPENAI_API_KEY="dmr" \
    MEM0_TELEMETRY="false" \
    NO_PROXY="localhost,127.0.0.1,host.docker.internal" \
    no_proxy="localhost,127.0.0.1,host.docker.internal"
