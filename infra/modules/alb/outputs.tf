output "dns_name" { value = aws_lb.api.dns_name }
output "load_balancer_arn" { value = aws_lb.api.arn }
output "security_group_id" { value = aws_security_group.alb.id }
output "target_group_arn" { value = aws_lb_target_group.api.arn }
output "listener_arn" { value = aws_lb_listener.http.arn }
output "load_balancer_arn_suffix" { value = aws_lb.api.arn_suffix }
output "target_group_arn_suffix" { value = aws_lb_target_group.api.arn_suffix }
