FROM python:3.13-alpine

COPY gateway-bootstrap.py /usr/local/bin/gateway-bootstrap.py

ENTRYPOINT ["python3", "/usr/local/bin/gateway-bootstrap.py"]
