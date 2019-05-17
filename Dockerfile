FROM crystallang/crystal:latest

ADD . /src
WORKDIR /src

# Build App
RUN shards build --production

# Extract dependencies
RUN ldd bin/rubber-soul | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Build a minimal docker image ontop of alpine linux
FROM alpine:latest
COPY --from=0 /src/deps /
COPY --from=0 /src/bin/rubber-soul /rubber-soul

HEALTHCHECK --interval=120s CMD wget --quiet --spider 127.0.0.1/3000/api/v1/healthz

# Run the app binding on port 3000
EXPOSE 3000
CMD ["./rubber-soul", "-b", "0.0.0.0", "-p", "3000"]
