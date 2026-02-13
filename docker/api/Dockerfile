FROM openjdk:11-jre-slim

# Install security updates
RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -g 1001 appgroup && \
    useradd -r -u 1001 -g appgroup appuser

WORKDIR /app

# Copy application
COPY target/analytics-api-*.jar app.jar
COPY application-prod.yml config/

# Security: Set proper permissions
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

# JVM optimization for containers
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"

ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar app.jar --spring.config.location=file:/app/config/"]
