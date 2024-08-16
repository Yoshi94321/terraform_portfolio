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
resource "aws_api_gateway_rest_api" "my_api" {
  name        = "SlackImageAPI"
  description = "Managed by Terraform"
}

# S3 Bucketsの定義
resource "aws_s3_bucket" "my_bucket1" {
  bucket = "recipe-7-7"
}

resource "aws_s3_bucket_acl" "my_bucket1_acl" {
  bucket = aws_s3_bucket.my_bucket1.id
  acl    = "private"
}

resource "aws_s3_bucket" "my_bucket2" {
  bucket = "recipe-upload-csv"
}

resource "aws_s3_bucket_acl" "my_bucket2_acl" {
  bucket = aws_s3_bucket.my_bucket2.id
  acl    = "private"
}


# SQS Queuesの定義
resource "aws_sqs_queue" "my_queue1" {
  name                              = "portfolio_SQS"
  visibility_timeout_seconds        = 30
  message_retention_seconds         = 345600
  max_message_size                  = 262144
  delay_seconds                     = 0
  receive_wait_time_seconds         = 0
  kms_data_key_reuse_period_seconds = 300
  fifo_queue                        = false
  content_based_deduplication       = false
  sqs_managed_sse_enabled           = true

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

resource "aws_sqs_queue" "my_queue2" {
  name                              = "portfolio-SQS2"
  visibility_timeout_seconds        = 30
  message_retention_seconds         = 345600
  max_message_size                  = 262144
  delay_seconds                     = 0
  receive_wait_time_seconds         = 0
  kms_data_key_reuse_period_seconds = 300
  fifo_queue                        = false
  content_based_deduplication       = false
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
resource "aws_lambda_function" "my_lambda1" {
  function_name = "SlackImageUploader"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = "arn:aws:iam::471112904122:role/service-role/SlackImageUploader-role-2sm3765q"
}

resource "aws_lambda_function" "my_lambda2" {
  function_name = "ProcessImage"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.process_image_role.arn

  environment {
    variables = {
      BUCKET_NAME = "recipe-7-7"
    }
  }

  s3_bucket        = "recipe-7-7"
  s3_key           = "slack-files/マカロン１.jpeg"
  source_code_hash = filebase64sha256("/Users/katouyoshinari/Desktop/lambda_function/lambda_function.py.zip")
}

resource "aws_lambda_function" "my_lambda3" {
  function_name = "upload-csv-recipes"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = "arn:aws:iam::471112904122:role/service-role/upload-csv-recipes-role-2oyktwax"
}

# S3 Notification to SQSの定義
resource "aws_s3_bucket_notification" "s3_event_to_sqs" {
  bucket = aws_s3_bucket.my_bucket1.id

  queue {
    queue_arn     = aws_sqs_queue.my_queue1.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".jpg"
  }

  depends_on = [aws_sqs_queue.my_queue1]
}

# SQS to Lambda Mappingの定義
resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.my_queue1.arn
  function_name    = aws_lambda_function.my_lambda2.arn
  enabled          = true
  batch_size       = 10
}

# DynamoDBの定義
resource "aws_dynamodb_table" "my_table" {
  name         = "SweetsRecipes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "SweetName"

  attribute {
    name = "SweetName"
    type = "S"
  }
}
