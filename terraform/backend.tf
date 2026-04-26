terraform {
  backend "s3" {
    bucket         = "cloud-sentinel-tf"  
    key            = "terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "cloud-sentinel-lockid"
  }
}