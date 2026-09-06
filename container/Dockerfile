# Minimal, non-root base image for running the agent sandbox.
FROM python:3.12-slim

# Create an unprivileged user/group to run as instead of root.
RUN groupadd --gid 1000 agent \
    && useradd --uid 1000 --gid agent --create-home --shell /bin/bash agent

# Workspace for agent code/data, owned by the non-root user.
RUN mkdir -p /workspace \
    && chown agent:agent /workspace

WORKDIR /workspace

# Drop root for all subsequent RUN/CMD/ENTRYPOINT instructions and at runtime.
USER agent
