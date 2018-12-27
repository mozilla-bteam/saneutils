FROM perl:5.28.0-slim
WORKDIR /app
RUN apt-get update && \
    apt-get install -y build-essential libssl-dev zlib1g-dev openssl nano vim
RUN cpanm --notest Carton

COPY cpanfile /app/cpanfile
RUN carton install

COPY lib/ /app/lib/
COPY edit-milestones.pl /app
COPY edit-versions.pl /app

CMD /bin/bash
