ARG ELASTIC_VERSION=8.19.7
FROM docker.elastic.co/beats/filebeat:${ELASTIC_VERSION}

COPY filebeat.yml /usr/share/filebeat/filebeat.yml

USER root
RUN chmod go-w /usr/share/filebeat/filebeat.yml
RUN chown root:root /usr/share/filebeat/filebeat.yml

USER filebeat
