# Multi-stage, multi-target Dockerfile for all three product components
# (matches the 3-container architecture in docs/architecture.md, kept as a
# single Dockerfile per the product-docker/ layout). Build a specific
# component with `--target`:
#   docker build --target api            -t analytics-api .
#   docker build --target webapp         -t analytics-web .
#   docker build --target data-processor -t analytics-data-processor .
# See build-scripts/ for wrappers around these commands.

# ---- shared base for the two JVM components ----
# openjdk:11-jre-slim was pulled from Docker Hub (the openjdk Official Image
# was deprecated by its maintainers and old tags were later removed) -
# eclipse-temurin is the actively-maintained, Debian-based successor, so the
# apt-get/groupadd/useradd lines below don't need to change.
FROM eclipse-temurin:11-jre-jammy AS jvm-base
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
RUN groupadd -g 1001 appgroup && useradd -r -u 1001 -g appgroup appuser
WORKDIR /app

# ---- api target ----
FROM jvm-base AS api
COPY target/analytics-api-*.jar app.jar
COPY application-prod.yml config/
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8080
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"
# additional-location (not location) - "location" REPLACES Spring Boot's
# default config search path instead of adding to it, which would silently
# drop the classpath application.yml that enables the actuator health-probe
# groups (/actuator/health/liveness, /actuator/health/readiness - what
# product-kubernetes/deployment.yaml's probes target) and the Prometheus
# endpoint (product-kubernetes/deployment.yaml's prometheus.io/* annotations).
ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar app.jar --spring.config.additional-location=file:/app/config/"]

# ---- data-processor target ----
FROM jvm-base AS data-processor
COPY target/analytics-data-processor-*.jar app.jar
RUN chown -R appuser:appgroup /app
USER appuser
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar app.jar"]

# ---- webapp target (static nginx, no JVM) ----
FROM nginx:1.21-alpine AS webapp
RUN addgroup -g 1001 -S appgroup && adduser -S appuser -u 1001 -G appgroup
COPY nginx.conf /etc/nginx/nginx.conf
COPY mime.types /etc/nginx/mime.types
COPY dist/ /usr/share/nginx/html/
RUN rm -f /etc/nginx/conf.d/default.conf && \
    chown -R appuser:appgroup /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
CMD ["nginx", "-g", "daemon off;"]
