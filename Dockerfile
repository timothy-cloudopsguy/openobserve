
# FROM public.ecr.aws/zinclabs/openobserve:v0.20.3 AS builder
FROM public.ecr.aws/zinclabs/openobserve-enterprise:v0.20.3 AS builder
FROM public.ecr.aws/debian/debian:trixie-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends curl iproute2

COPY --from=builder /openobserve /openobserve
COPY entrypoint.sh /entrypoint.sh

RUN ["/openobserve", "init-dir", "-p", "/data/"]
RUN ["chmod", "+x", "/entrypoint.sh"]

EXPOSE 5080

CMD ["/entrypoint.sh"]