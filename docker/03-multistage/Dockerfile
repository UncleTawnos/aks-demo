# ---- base: JDK + Maven + downloaded dependencies -------------------------
# Only pom.xml is copied here, so this slow layer is rebuilt only when the
# dependencies change, not on every code change.
FROM maven:3.9-eclipse-temurin-25 AS base
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline

# ---- localdev: what a developer runs on a laptop --------------------------
# No source code in the image: compose.yaml mounts ./src from the host.
FROM base AS localdev
CMD ["mvn", "-B", "spring-boot:run"]

# ---- build: compile and package the jar -----------------------------------
FROM base AS build
COPY src ./src
RUN mvn -B -DskipTests package

# ---- final: what goes to production ---------------------------------------
# JRE only: no Maven, no JDK, no source code. Runs as a non-root user.
FROM eclipse-temurin:25-jre AS final
RUN useradd --system --uid 10001 app
# Numeric ID, so Kubernetes can verify "runAsNonRoot" without reading /etc/passwd.
USER 10001
COPY --from=build /app/target/*.jar /app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app.jar"]
