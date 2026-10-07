# syntax=docker/dockerfile:1
#
# mem0 is an env-carrying overlay. It installs nothing into the image: the
# mem0ai wheel and the spaCy model land in the *composed base's* system Python
# at create time, via the lifecycle install hooks in mem0.yaml (a mixin overlay
# lands on an unknown base, so relocating site-packages here would not resolve).
#
# This recipe exists only to carry the runtime environment onto the composed
# image. v1 `environment.variables` becomes ENV, which is one of the additive
# image-config fields that merge at assembly - so a mixin's ENV *does* reach the
# composed image (only the contract fields entrypoint/cmd/user/workdir, which
# the workload anchors, are ignored). ENV must be on the recipe's final stage.
#
# `FROM scratch` keeps the layer purely the overlay: the frontend stages the
# descriptor as the single content layer and this ENV rides in the image config.
FROM scratch

# MIGRATION NOTE: v1 also set NO_PROXY / no_proxy so the mem0 client would reach
# the host's Docker Model Runner directly. Those are DROPPED here: the shell
# workload already defines NO_PROXY, and a mixin setting the same variable to a
# different value is a hard composition conflict ("env conflict on NO_PROXY").
# They are also unnecessary - the runtime network policy in mem0.yaml allows
# host.docker.internal:12434, and sbx enforces egress transparently at the proxy
# boundary regardless of the app-level NO_PROXY. OPENAI_* point the
# OpenAI-compatible client at the DMR; the api_key is the DMR sentinel "dmr", not
# a real credential - which is why this kit declares no credential@1.
ENV OPENAI_BASE_URL="http://host.docker.internal:12434/engines/v1" \
    OPENAI_API_KEY="dmr" \
    MEM0_TELEMETRY="false"
