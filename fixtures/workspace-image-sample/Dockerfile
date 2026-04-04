FROM spawn-base:latest

USER root
RUN printf '#!/bin/sh\nprintf "workspace-image-ok\\n"\n' > /usr/local/bin/workspace-image-smoke \
    && chmod +x /usr/local/bin/workspace-image-smoke
USER coder
