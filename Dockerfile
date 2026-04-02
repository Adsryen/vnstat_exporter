FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY vnstat_exporter.py .

EXPOSE 9469

ENTRYPOINT ["python3", "vnstat_exporter.py"]
