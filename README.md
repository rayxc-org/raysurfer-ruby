# Raysurfer Ruby SDK

[Website](https://www.raysurfer.com) · [Docs](https://docs.raysurfer.com) · [Dashboard](https://www.raysurfer.com/dashboard/api-keys)

AI maintained skills for vertical agents. Re-use verified code from prior runs rather than regenerating from scratch.

## Installation

```bash
gem install raysurfer-ruby
```

## Setup

```bash
export RAYSURFER_API_KEY=your_api_key_here
```

## Quickstart

```ruby
require "raysurfer"

client = Raysurfer::Client.new

search = client.search(task: "Generate quarterly report", top_k: 5)
puts "matches=#{search["total_found"]}"

upload = client.upload(
  task: "Generate quarterly report",
  file_written: {
    path: "report_generator.rb",
    content: "def run\n  puts 'ok'\nend\n"
  },
  succeeded: true,
  execution_logs: "Generated report successfully"
)
puts upload["message"]
```

## API

- `search(task:, top_k:, min_verdict_score:, min_human_upvotes:, prefer_complete:, input_schema:, workspace_id:, per_function_reputation:)`
- `store_code_block(name:, source:, entrypoint:, language:, ...)`
- `upload(task:, file_written:, succeeded:, ...)`
- `vote_code_snip(task:, code_block_id:, code_block_name:, code_block_description:, succeeded:)`

## Ruby + Existing Gem Workflows

Raysurfer works with Ruby-based systems via plain HTTP APIs under the hood. This gem wraps those endpoints with Ruby-friendly method names and request validation.
