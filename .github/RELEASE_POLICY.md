# Release policy / 发布策略

- 每次新发布都显式指定 `gh release create ... --latest`，不使用 `--prerelease` 或 `--latest=false`。GitHub 同时只有一个 Latest，随着新发布移动。
- Alpha/beta 仍保留版本后缀和明确的测试风险说明；Latest 不等于稳定版。
- 发布前必须通过回归测试、完整 ZIP 和 SHA-256 验证，发布后校验 `gh api repos/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/latest --jq .tag_name` 与新 tag 完全一致。
- 历史发布保持不可变；不重新打包或覆盖旧 tag 的资产。

Every new release explicitly uses `--latest`; retain alpha/beta version suffixes and documented validation limits. The latest endpoint must resolve to the new tag after publication.
