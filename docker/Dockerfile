FROM debian:wheezy 

ENV NEWQUE_VERSION 0.0.1

RUN apt-get -y update && apt-get install -y curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN curl -SLO "https://github.com/SGrondin/newque/releases/download/v0.0.1/newque.$NEWQUE_VERSION.tar.gz" \
    && tar xvf newque.$NEWQUE_VERSION.tar.gz \
    && rm newque.$NEWQUE_VERSION.tar.gz 

EXPOSE 8000 8001 8005

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN ln -s /newque/newque /usr/bin/newque

ENTRYPOINT ["/entrypoint.sh"]
CMD [ "newque" ]
