ARG CRYSTAL_VERSION=latest

FROM placeos/crystal:$CRYSTAL_VERSION as build
WORKDIR /app

# Setup commit via a build arg
ARG PLACE_COMMIT="DEV"
# Set the platform version via a build arg
ARG PLACE_VERSION="DEV"

# Create a non-privileged user, defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# See https://stackoverflow.com/a/55757473/12429735
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

# Install shards for caching
COPY shard.yml .
COPY shard.override.yml .
COPY shard.lock .

RUN shards install --production --ignore-crystal-version --skip-postinstall --skip-executables

# Add src
COPY ./src /app/src

# Compile
RUN UNAME_AT_COMPILE_TIME=true \
    PLACE_COMMIT=$PLACE_COMMIT \
    PLACE_VERSION=$PLACE_VERSION \
    shards build --production --error-trace

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Extract binary dependencies
RUN for binary in /app/bin/*; do \
        ldd "$binary" | \
        tr -s '[:blank:]' '\n' | \
        grep '^/' | \
        xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'; \
    done

# Create tmp directory with proper permissions
RUN rm -rf /tmp && mkdir -p /tmp && chmod 1777 /tmp

# Build a minimal docker image
FROM scratch
ENV PATH=$PATH:/
WORKDIR /

# Copy the user information over
COPY --from=build etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group

# These are required for communicating with external services
COPY --from=build /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Copy the app into place
COPY --from=build /app/deps /
COPY --from=build /app/bin /

# Copy tmp directory
COPY --from=build /tmp /tmp

# chmod for setting permissions on /tmp
COPY --from=build /bin /bin
COPY --from=build /lib/ld-musl-* /lib/
RUN chmod -R a+rwX /tmp
# hadolint ignore=SC2114,DL3059
RUN rm -rf /bin /lib

# Use an unprivileged user.
USER appuser:appuser

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/search-ingest"]
HEALTHCHECK CMD ["/search-ingest", "-c", "http://127.0.0.1:3000/api/search-ingest/v1"]
CMD ["/search-ingest", "-b", "0.0.0.0", "-p", "3000"]
