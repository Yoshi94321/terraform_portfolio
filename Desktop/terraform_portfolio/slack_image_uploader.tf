terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# API Gatewayの定義
resource "aws_api_gateway_rest_api" "SlackImageAPI" {
  name        = "SlackImageAPI"
  description = "Managed by Terraform"
}

# S3 Bucketsの定義
resource "aws_s3_bucket" "recipe-7-7" {
  bucket = "recipe-7-7"
}

resource "aws_s3_bucket" "recipe-upload-csv" {
  bucket = "recipe-upload-csv"
}

# Dead-letter queue (DLQ) の定義
resource "aws_sqs_queue" "portfolio_DLQ" {
  name                              = "portfolio_DLQ"
  visibility_timeout_seconds        = 30
  message_retention_seconds         = 1209600  # 14日間
  max_message_size                  = 262144
  delay_seconds                     = 0
  receive_wait_time_seconds         = 0
  kms_data_key_reuse_period_seconds = 300
  sqs_managed_sse_enabled           = true
}

# メインのSQSキューにデッドレターキューを設定
resource "aws_sqs_queue" "portfolio_SQS" {
  name                              = "portfolio_SQS"
  visibility_timeout_seconds        = 30
  message_retention_seconds         = 345600
  max_message_size                  = 262144
  delay_seconds                     = 0
  receive_wait_time_seconds         = 0
  kms_data_key_reuse_period_seconds = 300
  sqs_managed_sse_enabled           = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.portfolio_DLQ.arn
    maxReceiveCount     = 3
  })

  policy = jsonencode({
    Id = "S3ToSQSAccessPolicy"
    Statement = [
      {
        Action = "SQS:SendMessage"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:s3:*:*:recipe-7-7"
          }
          StringEquals = {
            "aws:SourceAccount" = "471112904122"
          }
        }
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Resource = "arn:aws:sqs:ap-northeast-1:471112904122:portfolio_SQS"
        Sid      = "example-statement-ID"
      }
    ]
    Version = "2012-10-17"
  })
}

# SQS Queuesの定義
resource "aws_sqs_queue" "portfolio-SQS2" {
  name                              = "portfolio-SQS2"
  visibility_timeout_seconds        = 30
  message_retention_seconds         = 345600
  max_message_size                  = 262144
  delay_seconds                     = 0
  receive_wait_time_seconds         = 0
  kms_data_key_reuse_period_seconds = 300
  sqs_managed_sse_enabled           = true

  policy = jsonencode({
    Id = "example-ID"
    Statement = [
      {
        Action = "SQS:SendMessage"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:s3:::recipe-upload-csv"
          }
          StringEquals = {
            "aws:SourceAccount" = "471112904122"
          }
        }
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Resource = "arn:aws:sqs:ap-northeast-1:471112904122:portfolio-SQS2"
        Sid      = "example-statement-ID"
      }
    ]
    Version = "2012-10-17"
  })
}

# IAM Role for Rekognitionの定義
resource "aws_iam_role" "process_image_role" {
  name = "ProcessImageRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "rekognition_policy" {
  name = "RekognitionPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rekognition:DetectLabels",
          "rekognition:DetectFaces",
          "rekognition:DetectModerationLabels",
          "rekognition:DetectText",
          "rekognition:RecognizeCelebrities"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rekognition_policy_attach" {
  role       = aws_iam_role.process_image_role.name
  policy_arn = aws_iam_policy.rekognition_policy.arn
}

# Lambda Functionsの定義
resource "aws_lambda_function" "SlackImageUploader" {
  function_name = "SlackImageUploader"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = "arn:aws:iam::471112904122:role/service-role/SlackImageUploader-role-2sm3765q"
}

resource "aws_lambda_function" "ProcessImage" {
  function_name = "ProcessImage"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.process_image_role.arn
}

resource "aws_lambda_function" "upload-csv-recipes" {
  function_name = "upload-csv-recipes"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = "arn:aws:iam::471112904122:role/service-role/upload-csv-recipes-role-2oyktwax"
}

# S3 Notification to SQSの定義
resource "aws_s3_bucket_notification" "s3_event_to_sqs" {
  bucket = aws_s3_bucket.recipe-7-7.id

  queue {
    queue_arn     = aws_sqs_queue.portfolio_SQS.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".jpg"
  }

  depends_on = [aws_sqs_queue.portfolio_SQS] 
}

# S3バケットのライフサイクルルール
resource "aws_s3_bucket_lifecycle_configuration" "recipe-7-7_lifecycle" {
  bucket = aws_s3_bucket.recipe-7-7.id

  rule {
    id     = "MoveToGlacierAndDelete"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 365  # 1年後に削除
    }
  }
}

# S3バケットのライフサイクルルール
resource "aws_s3_bucket_lifecycle_configuration" "recipe-upload-csv_lifecycle" {
  bucket = aws_s3_bucket.recipe-upload-csv.id

  rule {
    id     = "MoveToGlacierAndDelete"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 365  # 1年後に削除
    }
  }
}

# DynamoDBの定義
resource "aws_dynamodb_table" "SweetsRecipes" {
  name         = "SweetsRecipes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "SweetName"

  attribute {
    name = "SweetName"
    type = "S"
  }
}

