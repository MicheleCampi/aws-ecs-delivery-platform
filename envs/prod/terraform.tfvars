environment   = "prod"
vpc_cidr      = "10.30.0.0/16"
nat_mode      = "per_az"
desired_count = 2
# promoted from qa (A-010: digest sha256:e585ab77, healthz 200), D-0119
image_tag = "s3-yg8W516Bqkd9XP_1fM7Z9xRcrcgJFtAz"
