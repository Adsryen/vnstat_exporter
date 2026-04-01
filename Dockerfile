FROM debian:bullseye-slim

COPY vnstat-1.15.tar.gz /tmp/

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 python3-pip gcc make autoconf automake libc6-dev \
    && cd /tmp && tar -xzf vnstat-1.15.tar.gz \
    && cd /tmp/vnstat-1.15 && ./configure && make CFLAGS=-fcommon && make install \
    && cd /tmp && rm -rf vnstat-1.15 vnstat-1.15.tar.gz \
    && apt-get remove -y gcc make autoconf automake && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY vnstat_exporter.py .

EXPOSE 9469

ENTRYPOINT ["python3", "vnstat_exporter.py"]
