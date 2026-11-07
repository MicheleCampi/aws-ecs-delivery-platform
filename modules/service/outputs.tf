output "alb_dns_name" { value = aws_lb.this.dns_name }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "service_name" { value = aws_ecs_service.this.name }
output "execution_role_arn" { value = aws_iam_role.execution.arn }
output "alb_arn_suffix" { value = aws_lb.this.arn_suffix }
output "tg_arn_suffix" { value = aws_lb_target_group.this.arn_suffix }
