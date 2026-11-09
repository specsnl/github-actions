FROM busybox:1.37 AS base

FROM base AS app
RUN --mount=type=secret,id=e2e,env=E2E_SECRET test "$E2E_SECRET" = e2e-secret
CMD ["echo", "app"]

FROM base AS debian
ARG E2E_VERSION=dev
RUN echo "debian $E2E_VERSION" > /version
CMD ["cat", "/version"]

FROM base AS alpine
ARG E2E_VERSION=dev
RUN echo "alpine $E2E_VERSION" > /version
CMD ["cat", "/version"]
