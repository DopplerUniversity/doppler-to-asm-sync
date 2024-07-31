# Create build stage
FROM alpine:3.20

# Install dependencies
RUN apk add --no-cache \
  bash \
  wget \
  curl \
  jq \
  aws-cli

# Install Doppler CLI
RUN wget -q -t3 'https://packages.doppler.com/public/cli/rsa.8004D9FF50437357.key' -O /etc/apk/keys/cli@doppler-8004D9FF50437357.rsa.pub && \
  echo 'https://packages.doppler.com/public/cli/alpine/any-version/main' | tee -a /etc/apk/repositories && \
  apk add doppler

# Copy dependency files
COPY ./sync.sh /var/task/
COPY ./bootstrap /var/runtime/

ENV LAMBDA_TASK_ROOT=/var/task
ENV LAMBDA_RUNTIME_DIR=/var/runtime
ENV HOME=/tmp
ENV DOPPLER_CONFIG_DIR=/tmp/.doppler
ENV DOPPLER_ENABLE_VERSION_CHECK=false

ENTRYPOINT [ "/var/runtime/bootstrap" ]
CMD [ "sync.handler" ]