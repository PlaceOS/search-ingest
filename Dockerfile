FROM crystallang/crystal:0.32.1
ADD . /src
WORKDIR /src

# Build App
RUN shards build --error-trace --production

# Extract dependencies
RUN ldd bin/rubber-soul | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Build a minimal docker image
FROM scratch
WORKDIR /
ENV PATH=$PATH:/
COPY --from=0 /src/deps /
COPY --from=0 /src/bin/rubber-soul /rubber-soul

# These are required if your application needs to communicate with a database
# or any other external service where DNS is used to connect.
COPY --from=0 /lib/x86_64-linux-gnu/libnss_dns.so.2 /lib/x86_64-linux-gnu/libnss_dns.so.2
COPY --from=0 /lib/x86_64-linux-gnu/libresolv.so.2 /lib/x86_64-linux-gnu/libresolv.so.2
COPY --from=0 /etc/hosts /etc/hosts

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/rubber-soul"]
HEALTHCHECK CMD ["/rubber-soul", "-c", "http://127.0.0.1:3000/api/rubber-soul/v1"]
CMD ["/rubber-soul", "-b", "0.0.0.0", "-p", "3000"]
