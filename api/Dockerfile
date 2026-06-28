FROM public.ecr.aws/docker/library/eclipse-temurin:17-jdk AS build

WORKDIR /workspace/app

COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw && ./mvnw -q -DskipTests dependency:go-offline

COPY src src
RUN ./mvnw -q -DskipTests package

FROM public.ecr.aws/docker/library/eclipse-temurin:17-jre

WORKDIR /app

ENV JAVA_OPTS=""

COPY --from=build /workspace/app/target/video-stream-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
