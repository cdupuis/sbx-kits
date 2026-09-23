ARG DOODLE_TAG=2026
FROM docker/doodle:${DOODLE_TAG}

USER root

# docker/doodle is Alpine + busybox, which sits below the platform floor a
# workload owes its runtime (SPEC-v3 §12): no bash — which sbx@1 needs, as
# the agent is launched under it so BASH_ENV is sourced — no git or curl,
# no CA store, and an unprivileged uid 1000 named `bun` rather than
# `agent`. Renaming keeps the uid and gid, so /app stays owned by the user
# that runs the viewer and nothing needs a recursive chown.
#
# shadow is only here for usermod/groupmod and leaves with them.
RUN apk add --no-cache bash ca-certificates curl git \
 && apk add --no-cache --virtual .rename shadow \
 && usermod --login agent --home /home/agent --move-home --shell /bin/bash bun \
 && groupmod --new-name agent bun \
 && apk del .rename \
 && install -d -o agent -g agent /home/agent/workspace \
 && install -m 0644 -o agent -g agent /dev/null /etc/sandbox-persistent.sh

ENV BASH_ENV=/etc/sandbox-persistent.sh

USER agent
# Not the image's /app: sbx@1 places the workspace at the declared working
# directory, and a workspace mounted over /app would hide the viewer.
WORKDIR /home/agent/workspace
# Absolute, for the same reason — the entrypoint no longer runs from /app.
ENTRYPOINT ["bun", "/app/src/index.js"]
