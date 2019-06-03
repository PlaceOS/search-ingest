FROM crystallang/crystal:latest

ADD . /src
WORKDIR /src

# Build App
RUN shards build --production

# Extract dependencies
RUN ldd bin/rubber-soul | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Build a minimal docker image ontop of alpine linux
FROM busybox:glibc
COPY --from=0 /src/deps /
COPY --from=0 /src/bin/rubber-soul /rubber-soul

# Run the app binding on port 3000
EXPOSE 3000
CMD ["./rubber-soul", "-b", "0.0.0.0", "-p", "3000"]
