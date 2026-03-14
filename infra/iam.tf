# ── Role compartilhada pelas Lambdas ────────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "sptrans_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_s3" {
  name = "sptrans_lambda_s3_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*",
          aws_s3_bucket.static.arn,
          "${aws_s3_bucket.static.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3.arn
}

# ── Role do Step Functions ───────────────────────────────────────────────────
resource "aws_iam_role" "sfn_role" {
  name = "sptrans_sfn_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sfn_invoke_lambdas" {
  name = "sptrans_sfn_invoke_lambdas"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        aws_lambda_function.extractor.arn,
        aws_lambda_function.transformer.arn,
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sfn_invoke" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_invoke_lambdas.arn
}

# CloudWatch Logs para o Step Functions
resource "aws_iam_policy" "sfn_logs" {
  name = "sptrans_sfn_logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
                  "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutLogEvents",
                  "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sfn_logs" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_logs.arn
}

# ── Role do EventBridge para iniciar o Step Functions ───────────────────────
resource "aws_iam_role" "events_role" {
  name = "sptrans_events_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "events_start_sfn" {
  name = "sptrans_events_start_sfn"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [aws_sfn_state_machine.pipeline.arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "events_sfn" {
  role       = aws_iam_role.events_role.name
  policy_arn = aws_iam_policy.events_start_sfn.arn
}