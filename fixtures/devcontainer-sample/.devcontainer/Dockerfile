FROM spawn-base:latest

USER root
RUN printf '#!/bin/sh\nprintf "devcontainer-workspace-image-ok\\n"\n' > /usr/local/bin/devcontainer-smoke \
    && chmod +x /usr/local/bin/devcontainer-smoke
USER coder
