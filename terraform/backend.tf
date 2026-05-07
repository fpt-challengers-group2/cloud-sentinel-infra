terraform {
  backend "s3" {
    bucket         = "cloud-sentinel-tf-313712213904"  
    key            = "terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "cloud-sentinel-lockid"
  }
}