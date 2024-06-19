terraform {
  backend "s3" {
    bucket = "gatech-me-robojackets-bpm-preview-statefiles"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.54.1"
    }
  }
}

provider "aws" {
}

variable "ref" {
  type        = string
  description = "The git ref being deployed"
}

locals {
  s3_origin_id = "bpm-preview"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "gatech-me-robojackets-bpm-preview-${replace(var.ref, "/", "-")}"
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      type = "Service"
      identifiers = [
        "cloudfront.amazonaws.com",
      ]
    }

    condition {
      test = "StringEquals"
      values = [
        aws_cloudfront_distribution.cloudfront.arn
      ]
      variable = "AWS:SourceArn"
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.bucket.arn]

    principals {
      type = "Service"
      identifiers = [
        "cloudfront.amazonaws.com",
      ]
    }

    condition {
      test = "StringEquals"
      values = [
        aws_cloudfront_distribution.cloudfront.arn
      ]
      variable = "AWS:SourceArn"
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "aws_cloudfront_origin_access_control" "allow_cloudfront_access_to_s3" {
  name                              = "bpm-preview-${replace(var.ref, "/", "-")}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cloudfront" {
  origin {
    domain_name              = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.allow_cloudfront_access_to_s3.id
  }

  default_cache_behavior {
    allowed_methods        = ["HEAD", "GET", "OPTIONS"]
    cached_methods         = ["HEAD", "GET"]
    compress               = true
    viewer_protocol_policy = "https-only"
    target_origin_id       = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = "arn:aws:cloudfront::771971951923:function/dirhtml-uri-support"
    }
  }

  default_root_object = "index.html"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  http_version        = "http3"
  wait_for_deployment = false

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
    ssl_support_method             = "sni-only"
  }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.bucket.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.cloudfront.id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cloudfront.domain_name
}
