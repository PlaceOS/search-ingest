ARG CRYSTAL_VERSION=1.1.1
FROM crystallang/crystal:${CRYSTAL_VERSION}-alpine as build

# Setup commit via a build arg
ARG PLACE_COMMIT="DEV"

WORKDIR /app

# Add trusted CAs for communicating with external services
RUN apk update && \
    apk add --no-cache \
      ca-certificates \
    && \
    update-ca-certificates

# Install shards for caching
COPY shard.yml .
COPY shard.override.yml .
COPY shard.lock .

RUN shards install --production --ignore-crystal-version

# Add src
COPY ./src /app/src

# Compile
RUN PLACE_COMMIT=$PLACE_COMMIT \
    crystal build --release --no-debug --error-trace /app/src/app.cr -o /app/rubber-soul

# Extract dependencies
RUN ldd /app/rubber-soul | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Build a minimal docker image
FROM scratch
WORKDIR /

COPY --from=build /app/deps /
COPY --from=build /app/rubber-soul /rubber-soul

# These are required for communicating with external services
COPY --from=build /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

ENV PATH=$PATH:/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/rubber-soul"]
HEALTHCHECK CMD ["/rubber-soul", "-c", "http://127.0.0.1:3000/api/rubber-soul/v1"]
CMD ["/rubber-soul", "-b", "0.0.0.0", "-p", "3000"]
