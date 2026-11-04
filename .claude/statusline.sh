#!/bin/bash
# 標準入力の JSON からステータスラインを生成する
jq -r '"\(.model.display_name // "Claude") | \(.context_window.total_input_tokens // 0)/\(.context_window.total_output_tokens // 0) tokens | Context: \(.context_window.used_percentage // 0)% used | \((.cost.total_api_duration_ms // 0) / 1000 * 10 | round / 10)s"'
