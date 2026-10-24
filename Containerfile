# Your plugin's image. BASE is the released base in base.txt: the sandbox's own root (Debian 13 with
# the window stack), which every sandbox already has, so only what you add here is downloaded. The
# store refuses any other FROM. Clean apt's caches in the same RUN, or they ship with your app.
ARG BASE
FROM ${BASE}
# Install what your app needs from Debian's archive, for example:
# RUN apt-get update && apt-get install -y --no-install-recommends htop && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh
