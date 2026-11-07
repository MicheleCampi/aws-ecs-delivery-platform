# Plan-only tests with a mocked provider: no AWS credentials, no cost.
mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.this
    values = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
}

variables {
  name = "test"
}

run "none_has_no_egress" {
  command = plan
  variables { nat_mode = "none" }
  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_route.private_egress) == 0
    error_message = "none must create no NAT and no egress route"
  }
}

run "single_shares_one_nat" {
  command = plan
  variables { nat_mode = "single" }
  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_route.private_egress) == 2
    error_message = "single must create 1 NAT shared by 2 private route tables"
  }
}

run "per_az_one_nat_per_az" {
  command = plan
  variables {
    nat_mode = "per_az"
    az_count = 3
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_subnet.private) == 3
    error_message = "per_az with 3 AZ must create 3 NAT and 3 private subnets"
  }
}

run "rejects_unknown_nat_mode" {
  command = plan
  variables { nat_mode = "double" }
  expect_failures = [var.nat_mode]
}

run "rejects_single_az" {
  command = plan
  variables { az_count = 1 }
  expect_failures = [var.az_count]
}
