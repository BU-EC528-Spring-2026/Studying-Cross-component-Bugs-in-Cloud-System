FROM python:3.12-slim

WORKDIR /app

COPY bin ./bin
COPY docs ./docs
COPY examples ./examples
COPY policies ./policies
COPY README.md .
COPY ENVIRONMENT_PROFILE.md .

RUN chmod +x /app/bin/*.py

CMD ["bash"]
