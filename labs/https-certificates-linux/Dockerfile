# Self-contained Linux lab box for the HTTPS / certificates hands-on activity.
# Pre-installs everything Lab 2 (labs/02-https-certificates-linux.md) needs so
# learners can `docker compose up` and start the exercises immediately instead
# of running `apt install` by hand first.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssl \
        nginx \
        apache2 \
        certbot \
        python3-certbot-nginx \
        curl \
        cron \
        procps \
        vim \
        iproute2 \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Apache's ssl module is needed for Part 4.2 of the lab.
RUN a2enmod ssl

# Keep the container alive so learners can `docker exec` in and drive each
# step interactively; nginx/apache/cron are started manually during the lab
# (see README.md) since this image has no init system (systemd).
CMD ["sleep", "infinity"]
