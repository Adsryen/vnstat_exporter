FROM python:3.11-slim

RUN apt-get update && apt-get install -y vnstat && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY vnstat_exporter.py .

EXPOSE 9469

ENTRYPOINT ["python3", "vnstat_exporter.py"]
