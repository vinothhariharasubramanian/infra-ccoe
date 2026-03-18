# Project Context for Claude Code
 
## Integration Setup
- Claude Code is connected to **GitHub** via MCP server
- Backend: **AWS Bedrock** (no direct Anthropic API key needed)
- Auth: AWS SSO via IAM profile
 
## What Claude Can Do via GitHub MCP
- Read/search repositories, files, issues, PRs
- Create branches, commits, pull requests
- Post comments on PRs and issues
- Search code across the repo
 
## Key Commands to Try in Demo
- "List open PRs in this repo"
- "Create a branch called feature/demo and add a README change"
- "Review the latest PR and suggest improvements"
- "Find all TODO comments in the codebase"
- "Open a new issue titled 'Demo issue from Claude Code'"
 
## AWS Bedrock Notes
- Model: Claude Sonnet 4.5 (cross-region inference profile)
- Region: us-east-1
- Credentials via AWS SSO profile (no static keys)