variable "account_number" {
  type        = string
  description = "The AWS account number."
}

resource "aws_cloudwatch_event_rule" "run_instances" {
  name        = "capture-ec2-run-instances"
  description = "Capture each EC2 RunInstances event"

  event_pattern = <<EOF
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
      "eventSource": ["ec2.amazonaws.com"],
      "eventName": "RunInstances"
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "lambda" {
  target_id = "SendToLambda"
  rule      = aws_cloudwatch_event_rule.run_instances.name
  arn       = aws_lambda_function.lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.run_instances.arn
  qualifier     = aws_lambda_alias.lambda_alias.name
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "latest-alias"
  function_name    = aws_lambda_function.lambda.function_name
  function_version = "$LATEST"
}

resource "aws_iam_policy_attachment" "attach" {
  name       = "attachment"
  roles      = [aws_iam_role.iam_for_lambda.name]
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_iam_policy" "policy" {
  name        = "lambda_policy"
  path        = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Sid": "ec2ResourceAutoTaggerObserveAnnotate",
        "Effect": "Allow",
        "Action": [
            "cloudwatch:PutMetricData",
            "ec2:DescribeInstances",
            "ec2:DescribeVolumes"
        ],
        "Resource": "*"
      },
      {
        "Sid": "ec2ResourceAutoTaggerCreateUpdate",
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogStream",
            "ec2:CreateTags",
            "logs:CreateLogGroup",
            "logs:PutLogEvents"
        ],
        "Resource": [
            "arn:aws:ec2:*:${var.account_number}:instance/*",
            "arn:aws:ec2:*:${var.account_number}:volume/*",
            "arn:aws:logs:eu-east-1:${var.account_number}:log-group:/aws/lambda/${aws_lambda_function.lambda.function_name}:log-stream:*",
            "arn:aws:logs:eu-east-1:${var.account_number}:log-group:/aws/lambda/${aws_lambda_function.lambda.function_name}"
        ]
      },
      {
        "Sid": "ec2ResourceAutoTaggerRead",
        "Effect": "Allow",
        "Action": [
            "iam:ListRoleTags",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:GetLogEvents",
            "ssm:GetParametersByPath"
        ],
        "Resource": [
            "arn:aws:iam::${var.account_number}:role/*",
            "arn:aws:logs:eu-east-1:${var.account_number}:log-group:/aws/lambda/${aws_lambda_function.lambda.function_name}:log-stream:*",
            "arn:aws:logs:eu-east-1:${var.account_number}:log-group:/aws/lambda/${aws_lambda_function.lambda.function_name}",
            "arn:aws:ssm:*:${var.account_number}:parameter/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": []
  })
}

data "archive_file" "lambda_zip_dir" {
  type        = "zip"
  output_path = "/tmp/lambda_zip_dir.zip"
	source_dir  = "source"
}

resource "aws_lambda_function" "lambda" {
  function_name = "resource-auto-tagger"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "main.lambda_handler"
  
  filename         = "${data.archive_file.lambda_zip_dir.output_path}"
  source_code_hash = "${data.archive_file.lambda_zip_dir.output_base64sha256}"

  runtime = "python3.9"

  environment {
    variables = {
      environment = "sandbox",
      project = "auto-tagging"
    }
  }
}