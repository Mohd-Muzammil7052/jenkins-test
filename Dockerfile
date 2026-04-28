FROM eclipse-temurin:21-jdk-alpine

RUN apk add --no-cache wget

WORKDIR /app

COPY target/*.jar app.jar

EXPOSE 8080

CMD ["java", "-jar", "app.jar"]