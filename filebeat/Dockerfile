ARG ELASTIC_VERSION=8.12.1
FROM docker.elastic.co/beats/filebeat:${ELASTIC_VERSION}

USER root

COPY config/filebeat.docker.yml /usr/share/filebeat/filebeat.yml

RUN chown root:root /usr/share/filebeat/filebeat.yml && \
    chmod 0644 /usr/share/filebeat/filebeat.yml
