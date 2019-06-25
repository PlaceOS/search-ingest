FROM crystallang/crystal:latest

ADD . /src
WORKDIR /src

RUN apt-get update -dd
RUN apt-get install -y curl

# Build App
RUN shards install
RUN shards build --production

# Extract dependencies
RUN ldd bin/rubber-soul | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

FROM busybox:glibc
COPY --from=0 /src/deps /
COPY --from=0 /src/bin/rubber-soul /rubber-soul

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget --spider localhost:3000/api/v1
CMD ["./rubber-soul", "-b", "0.0.0.0", "-p", "3000"]
