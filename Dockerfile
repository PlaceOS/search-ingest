ARG crystal_version=1.1.0
FROM crystallang/crystal:${crystal_version}-alpine

# Setup commit via a build arg
ARG PLACE_COMMIT="DEV"

WORKDIR /app

# Add trusted CAs for communicating with external services
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
      ca-certificates

RUN update-ca-certificates

# Install shards for caching
COPY shard.yml .
COPY shard.override.yml .
COPY shard.lock .

RUN shards install --production --ignore-crystal-version

# Add src
ADD ./src /app/src

# Compile
RUN PLACE_COMMIT=$PLACE_COMMIT \
    crystal build --release --no-debug --error-trace /app/src/app.cr -o /app/rubber-soul

# Extract dependencies
RUN ldd /app/rubber-soul | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Build a minimal docker image
FROM scratch
WORKDIR /

COPY --from=0 /app/deps /
COPY --from=0 /app/rubber-soul /rubber-soul

# These are required for communicating with external services
COPY --from=0 /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=0 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# This is required for Timezone support
COPY --from=0 /usr/share/zoneinfo/ /usr/share/zoneinfo/

ENV PATH=$PATH:/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/rubber-soul"]
HEALTHCHECK CMD ["/rubber-soul", "-c", "http://127.0.0.1:3000/api/rubber-soul/v1"]
CMD ["/rubber-soul", "-b", "0.0.0.0", "-p", "3000"]
