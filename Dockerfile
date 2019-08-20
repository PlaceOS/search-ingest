FROM acalabs/crystal-alpine:0.30.1 as builder

# Install shards for caching
COPY shard.yml shard.yml
RUN shards install --production

# Add src
COPY . ./

# Manually remake libscrypt, PostInstall fails inexplicably
RUN make -C ./lib/scrypt/ clean
RUN make -C ./lib/scrypt/

# Build application
RUN crystal build src/rubber-soul.cr --release --no-debug --static

# Compress static executable
RUN upx --best rubber-soul

# Build a minimal docker image
FROM alpine:3.10
COPY --from=builder rubber-soul rubber-soul

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget --spider localhost:3000/healthz
CMD ["/rubber-soul", "-b", "0.0.0.0", "-p", "3000"]
