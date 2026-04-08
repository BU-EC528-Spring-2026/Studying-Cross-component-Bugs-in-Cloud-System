FROM python:3.12-slim

WORKDIR /app

# Copy prototype scripts into bin/
COPY prototype/capture_submit_intent.py ./bin/capture_submit_intent.py
COPY prototype/configprop_guard.py      ./bin/configprop_guard.py

# Copy supporting data
COPY prototype/examples  ./examples
COPY prototype/policies  ./policies

# Copy docs
COPY prototype/README.md              ./docs/README.md
COPY prototype/ENVIRONMENT_PROFILE.md ./ENVIRONMENT_PROFILE.md
COPY README.md                        ./README.md

# Copy and prepare demo runner
COPY sprint3_test_demo.sh ./sprint3_test_demo.sh

# Create reports directory and set permissions
RUN mkdir -p /app/reports && chmod +x /app/bin/*.py /app/sprint3_test_demo.sh

CMD ["./sprint3_test_demo.sh"]
