terraform {
  backend "s3" {
    bucket         = "cloud-sentinel-tfstate"  
    key            = "terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "cloud-sentinel-lockid"
  }
}