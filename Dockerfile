FROM alpine:3.8 as build
LABEL maintainer="Denys Zhdanov <denis.zhdanov@gmail.com>"

RUN true \
 && apk add --update \
      alpine-sdk \
      cairo \
      git \
      libffi-dev \
      librrd \
      nginx \
      pkgconfig \
      py3-cairo \
      py3-pip \
      py3-pyldap \
      py3-virtualenv \
      py-rrd \
      python3-dev \
      rrdtool-dev \
      sqlite \
      wget \
 && virtualenv /opt/graphite \
 && . /opt/graphite/bin/activate \
 && pip3 install \
      django==1.11.15 \
      django-statsd-mozilla \
      fadvise \
      gunicorn \
      msgpack-python \
      redis \
      rrdtool

ARG version=1.1.4

# install whisper
ARG whisper_version=${version}
ARG whisper_repo=https://github.com/graphite-project/whisper.git
RUN git clone -b ${whisper_version} --depth 1 ${whisper_repo} /usr/local/src/whisper \
 && cd /usr/local/src/whisper \
 && . /opt/graphite/bin/activate \
 && python3 ./setup.py install

# install carbon
ARG carbon_version=${version}
ARG carbon_repo=https://github.com/graphite-project/carbon.git
RUN . /opt/graphite/bin/activate \
 && git clone -b ${carbon_version} --depth 1 ${carbon_repo} /usr/local/src/carbon \
 && cd /usr/local/src/carbon \
 && pip3 install -r requirements.txt \
 && python3 ./setup.py install

# install graphite
ARG graphite_version=${version}
ARG graphite_repo=https://github.com/graphite-project/graphite-web.git
RUN . /opt/graphite/bin/activate \
 && git clone -b ${graphite_version} --depth 1 ${graphite_repo} /usr/local/src/graphite-web \
 && cd /usr/local/src/graphite-web \
 && pip3 install -r requirements.txt \
 && python3 ./setup.py install

# fixing RRD support (see https://github.com/graphite-project/docker-graphite-statsd/issues/63)
RUN sed -i \
's/return os.path.realpath(fs_path)/return os.path.realpath(fs_path).decode("utf-8")/' \
/opt/graphite/webapp/graphite/readers/rrd.py

# installing nodejs 6
ARG NODEJS_VERSION=6.14.4
RUN wget -q -O - https://nodejs.org/download/release/v${NODEJS_VERSION}/node-v${NODEJS_VERSION}-linux-x64.tar.gz \
  | tar xz -C /opt \
 && mv /opt/node-v${NODEJS_VERSION}-linux-x64 /opt/nodejs

# install statsd
ARG statsd_version=v0.8.0
ARG statsd_repo=https://github.com/etsy/statsd.git
RUN git clone -b ${statsd_version} --depth 1 ${statsd_repo} /opt/statsd

# config graphite
COPY conf/opt/graphite/conf/*.conf /opt/graphite/conf/
COPY conf/opt/graphite/webapp/graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
WORKDIR /opt/graphite/webapp
RUN mkdir -p /var/log/graphite/ \
  && PYTHONPATH=/opt/graphite/webapp /opt/graphite/bin/django-admin.py collectstatic --noinput --settings=graphite.settings

# config statsd
COPY conf/opt/statsd/config_*.js /opt/statsd/

FROM alpine:3.8 as production
LABEL maintainer="Denys Zhdanov <denis.zhdanov@gmail.com>"

ENV STATSD_INTERFACE udp

RUN true \
 && apk add --update \
      cairo \
      collectd \
      collectd-disk \
      collectd-nginx \
      findutils \
      librrd \
      memcached \
      nginx \
      py3-pyldap \
      redis \
      sqlite \
 && rm -rf \
      /etc/nginx/conf.d/default.conf \
 && mkdir -p \
      /var/log/carbon \
      /var/log/graphite

COPY conf /
COPY conf /etc/graphite-statsd/conf/

# copy /opt from build image
COPY --from=build /opt /opt


# defaults
EXPOSE 80 2003-2004 2023-2024 8080 8125 8125/udp 8126
VOLUME ["/opt/graphite/conf", "/opt/graphite/storage", "/opt/graphite/webapp/graphite/functions/custom", "/etc/nginx", "/opt/statsd", "/etc/logrotate.d", "/var/log", "/var/lib/redis"]

CMD ["/sbin/my_init"]
