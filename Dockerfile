FROM python:3.10-slim AS test
WORKDIR /app
COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY src ./src
COPY tests ./tests
RUN pytest

FROM python:3.10-slim AS run
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --from=test /app/src .
ENTRYPOINT ["python", "main.py"]