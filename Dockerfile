FROM public.ecr.aws/lambda/python:3.12

RUN dnf install -y gcc-c++

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY src/lambda_handler.py ${LAMBDA_TASK_ROOT}

CMD [ "lambda_handler.handler" ]