FROM perl:5.28.0-slim
WORKDIR /app
RUN apt-get update
RUN apt-get install -y build-essential libssl-dev zlib1g-dev openssl

RUN cpanm --notest Carton

COPY cpanfile /app/cpanfile
COPY lib/ /app/lib/
COPY edit-milestones.pl /app

