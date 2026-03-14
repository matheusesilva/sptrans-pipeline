# ── CloudFront + WAF + Origin Access Control ────────────────────────────────

# Note: OAC is defined in s3.tf to avoid circular dependencies

# ── 1. WAF – Rate Limiting (500 requests per 5 minutes per IP) ──────────────
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  name        = "sptrans-cloudfront-waf"
  description = "WAF for CloudFront - Rate limiting and IP blocking"
  scope       = "CLOUDFRONT"
  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 500
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "sptrans-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}

  # ── 2. CloudFront Distribution ──────────────────────────────────────────────
resource "aws_cloudfront_distribution" "static" {
  origin {
    domain_name            = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id              = "s3-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  enabled             = true
  default_root_object = "index.html"
  http_version        = "http2and3"

  # ── Caching behavior ────────────────────────────────────────────────────
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static"

    # CloudFront managed policy - optimized for static content
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # ── Cache behavior for Parquet data (longer TTL) ─────────────────────────
  ordered_cache_behavior {
    path_pattern     = "/data/gold/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static"

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # ── Error pages ──────────────────────────────────────────────────────────
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 403
    response_page_path = "/index.html"
  }

  # ── WAF Association ──────────────────────────────────────────────────────
  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn

  # ── Restrictions ────────────────────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ── SSL/TLS ──────────────────────────────────────────────────────────────
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [aws_s3_bucket_public_access_block.static]

  tags = {
    Name = "sptrans-cloudfront"
  }
}

# ── 3. CloudWatch Alarm for Rate Limiting ────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "waf_rate_limit_triggered" {
  alarm_name          = "sptrans-waf-rate-limit-triggered"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alert when WAF rate limiting blocks 10+ requests in 5 min"
  alarm_actions       = []

  dimensions = {
    WebACL = aws_wafv2_web_acl.cloudfront_waf.name
    Rule   = "RateLimitRule"
    Region = var.aws_region
  }
}
