resource "aws_cloudwatch_log_group" "sfn_logs" {
  name              = "/aws/states/sptrans-pipeline"
  retention_in_days = 7
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "sptrans-pipeline"
  role_arn = aws_iam_role.sfn_role.arn

  # Express Workflow: execução rápida, ideal para pipelines de menos de 5 min
  type = "EXPRESS"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  definition = jsonencode({
    Comment = "Pipeline SPTrans: Extração (Bronze) → Transformação (Silver + Gold)"
    StartAt = "Extrair"

    States = {
      Extrair = {
        Type     = "Task"
        Comment  = "Chama o Lambda Extrator e recebe o caminho do arquivo Bronze"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.extractor.arn
          "Payload.$"  = "$"
        }
        # Propaga apenas o Payload para o próximo estado
        ResultSelector = {
          "bronze_key.$" = "$.Payload.bronze_key"
          "bucket.$"     = "$.Payload.bucket"
        }
        ResultPath = "$"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 5
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "FalhaExtracao"
        }]
        Next = "Transformar"
      }

      Transformar = {
        Type     = "Task"
        Comment  = "Chama o Lambda Transformer com DuckDB; grava Silver e Gold"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.transformer.arn
          "Payload.$"  = "$"
        }
        ResultPath = "$.transform_result"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 10
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "FalhaTransformacao"
        }]
        End = true
      }

      FalhaExtracao = {
        Type  = "Fail"
        Error = "ExtractorError"
        Cause = "O Lambda Extrator retornou um erro. Verifique os logs do CloudWatch."
      }

      FalhaTransformacao = {
        Type  = "Fail"
        Error = "TransformerError"
        Cause = "O Lambda Transformer retornou um erro. Verifique os logs do CloudWatch."
      }
    }
  })
}