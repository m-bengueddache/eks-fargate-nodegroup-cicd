FROM eclipse-temurin:21-jdk
EXPOSE 8080
RUN mkdir /opt/app
COPY build/libs/*.jar /opt/app/app.jar
WORKDIR /opt/app
CMD ["java", "-jar", "app.jar"]