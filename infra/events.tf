resource "aws_cloudwatch_event_rule" "every_5_minutes" {
  name                = "sptrans-pipeline-every-5-minutes"
  description         = "Inicia o pipeline SPTrans a cada 5 minutos via Step Functions"
  schedule_expression = "rate(5 minutes)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "step_functions" {
  rule      = aws_cloudwatch_event_rule.every_5_minutes.name
  target_id = "SptransPipeline"
  arn       = aws_sfn_state_machine.pipeline.arn
  role_arn  = aws_iam_role.events_role.arn

  input = jsonencode({})
}