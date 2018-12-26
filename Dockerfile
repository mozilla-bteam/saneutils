FROM perl:5.28.0-slim
WORKDIR /app
RUN apt-get update
RUN apt-get install -y build-essential libssl-dev zlib1g-dev openssl

COPY cpanfile /app/cpanfile
RUN cpanm --notest --installdeps -l /app/local .

COPY lib/ /app/lib/
COPY edit-milestones.pl /app

