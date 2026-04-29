terraform {
  backend "s3" {
    bucket         = "cloud-sentinel-tf-154959838182-us"  
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "cloud-sentinel-lockid"
  }
}