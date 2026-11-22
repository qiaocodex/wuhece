FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o /app/boxbook-server

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/boxbook-server /app/boxbook-server
COPY --from=build /app/web /app/web
ENV PORT=8800
ENV DB_PATH=/data/boxbook.db
VOLUME ["/data"]
EXPOSE 8800
CMD ["/app/boxbook-server"]
