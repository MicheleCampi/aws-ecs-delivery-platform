terraform {
  backend "s3" {
    bucket       = "michele-tfstate-aws-ecs-delivery"
    key          = "bootstrap/github-oidc.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
