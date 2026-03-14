# Stage 1: The Builder
FROM public.ecr.aws/lambda/python:3.12 AS builder

RUN dnf install -y gcc-c++ 

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

# Stage 2: The Final Runner
FROM public.ecr.aws/lambda/python:3.12

COPY --from=builder ${LAMBDA_TASK_ROOT} ${LAMBDA_TASK_ROOT}

COPY handler.py ${LAMBDA_TASK_ROOT}

RUN python -c "import duckdb; conn = duckdb.connect(); conn.execute('INSTALL h3 FROM community; INSTALL httpfs;')"

CMD ["handler.handler"]