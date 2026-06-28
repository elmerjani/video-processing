output "api_id" { value = aws_apigatewayv2_api.this.id }
output "api_endpoint" { value = aws_apigatewayv2_api.this.api_endpoint }
output "invoke_url" { value = "${aws_apigatewayv2_api.this.api_endpoint}/${aws_apigatewayv2_stage.this.name}" }
output "stage_name" { value = aws_apigatewayv2_stage.this.name }
