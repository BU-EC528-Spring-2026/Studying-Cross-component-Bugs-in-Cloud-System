FROM python:3.12-slim

WORKDIR /app

COPY bin ./bin
COPY docs ./docs
COPY examples ./examples
COPY policies ./policies
COPY README.md .
COPY ENVIRONMENT_PROFILE.md .
COPY entrypoint.sh .
COPY run_case1.sh .
COPY run_case2.sh .

RUN chmod +x /app/bin/*.py /app/entrypoint.sh /app/run_case1.sh /app/run_case2.sh

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["help"]
