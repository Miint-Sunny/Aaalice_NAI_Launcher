#!/bin/bash
# Tests that need a real macOS host, plus the seams changed by upstream 2.2.4.
# Uses fixtures only; does not start the application or call a live NAI API.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test --no-pub --concurrency=3 \
  test/presentation/wiring/resource_window_opener_test.dart \
  test/app_exit_shortcuts_test.dart \
  test/core/services/mac_legacy_data_import_test.dart \
  test/core/services/mac_legacy_data_sync_test.dart \
  test/core/rag/rag_platform_test.dart \
  test/core/utils/file_sha256_test.dart \
  test/core/utils/studio_sandbox_test.dart \
  test/core/nai_agent/node_runtime_environment_test.dart \
  test/presentation/providers/nai_agent/agent_management_test.dart \
  test/app_test.dart \
  test/presentation/wiring/settings_storage_inventory_test.dart \
  test/presentation/providers/nai_agent/nai_agent_builtin_skills_path_test.dart \
  test/core/network/system_proxy_reader_test.dart \
  test/presentation/providers/detected_system_proxy_test.dart \
  test/presentation/providers/nai_agent/inventory_cache_test.dart \
  test/presentation/providers/nai_agent/skill_command_lists_test.dart \
  test/presentation/providers/nai_agent/host_reaper_test.dart \
  test/presentation/providers/nai_agent/package_inventory_refresh_test.dart \
  test/core/database/asset_database_manager_test.dart \
  test/presentation/providers/generation/generation_retry_policy_test.dart \
  test/presentation/providers/generation/image_generation_retry_test.dart \
  test/presentation/wiring/generation_error_view_test.dart \
  test/presentation/wiring/generation_data_wiring_test.dart \
  test/presentation/wiring/generation_canvas_wiring_test.dart
