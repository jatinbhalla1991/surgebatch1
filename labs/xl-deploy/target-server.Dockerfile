# linuxserver/openssh-server (Alpine-based) is purpose-built for the SSH/SFTP
# connection XL Deploy's overthere.SshHost needs - it is not an application
# runtime. We layer a JRE on top so the jar that XL Deploy deploys here can
# also be executed directly on this host, instead of needing a separate
# container just to run and verify it.
FROM linuxserver/openssh-server:latest
RUN apk add --no-cache openjdk17-jre
