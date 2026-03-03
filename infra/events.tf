# 1. Define a regra de tempo (O Cron)
resource "aws_cloudwatch_event_rule" "sptrans_every_5_minutes" {
  name                = "sptrans-extract-every-5-minutes"
  description         = "Dispara o Lambda da SPTrans a cada 5 minutos"
  schedule_expression = "rate(5 minutes)"
}

# 2. Conecta a regra ao Lambda
resource "aws_cloudwatch_event_target" "target_lambda" {
  rule      = aws_cloudwatch_event_rule.sptrans_every_5_minutes.name
  target_id = "SptransExtractor"
  arn       = aws_lambda_function.sptrans_pipeline.arn
}

# 3. Dá permissão para o EventBridge invocar o Lambda
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sptrans_pipeline.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sptrans_every_5_minutes.arn
}