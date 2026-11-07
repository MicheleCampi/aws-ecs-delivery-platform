output "pipeline_name" { value = aws_codepipeline.this.name }
output "artifact_bucket" { value = aws_s3_bucket.artifacts.bucket }
output "source_key" { value = local.source_key }
