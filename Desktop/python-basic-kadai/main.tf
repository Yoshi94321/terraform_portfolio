terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  profile = "default"  # 使いたいAWS CLIのプロファイルを指定
  region  = "ap-northeast-1"  # 使用するリージョンを指定（例: 東京リージョン）
}

resource "aws_s3_bucket" "test_bucket" {
  bucket = "my-test-bucket-samurai-test"  # バケット名を指定
  acl    = "private"  # アクセス制御リスト（ACL）を指定（例: private）

  tags = {
    Name        = "Test S3 Bucket"
    Environment = "Test"
  }
}
