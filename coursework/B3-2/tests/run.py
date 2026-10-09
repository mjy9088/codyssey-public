from test_api_transport import test_api_authentication_error_is_key_safe
from test_api_transport import test_api_malformed_json_is_key_safe
from test_api_transport import test_api_missing_output_text_is_key_safe
from test_api_transport import test_api_rate_limit_error_is_key_safe
from test_api_transport import test_api_server_error_is_key_safe
from test_api_transport import test_api_success_uses_fixed_endpoint_and_expected_request_shape
from test_git_cli import test_api_backend_requires_explicit_network_opt_in
from test_git_cli import test_cli_fixture_default_needs_no_key_or_network
from test_git_cli import test_cli_reports_clean_repository
from test_git_cli import test_collect_changes_reads_status_and_worktree_diff
from test_review import test_fixture_commit_is_valid_and_uses_changed_files
from test_review import test_fixture_pr_contains_required_sections_and_bullets
from test_review import test_prompt_contains_parameters_but_not_instructions_from_diff
from test_review import test_safe_mode_masks_secrets_and_bounds_diff
from test_review import test_validator_rejects_overlong_commit_title


def main() -> None:
    tests = [
        test_safe_mode_masks_secrets_and_bounds_diff,
        test_fixture_commit_is_valid_and_uses_changed_files,
        test_fixture_pr_contains_required_sections_and_bullets,
        test_prompt_contains_parameters_but_not_instructions_from_diff,
        test_validator_rejects_overlong_commit_title,
        test_collect_changes_reads_status_and_worktree_diff,
        test_cli_fixture_default_needs_no_key_or_network,
        test_cli_reports_clean_repository,
        test_api_backend_requires_explicit_network_opt_in,
        test_api_success_uses_fixed_endpoint_and_expected_request_shape,
        test_api_authentication_error_is_key_safe,
        test_api_rate_limit_error_is_key_safe,
        test_api_server_error_is_key_safe,
        test_api_malformed_json_is_key_safe,
        test_api_missing_output_text_is_key_safe,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print(f"ALL TESTS PASSED ({len(tests)})")


if __name__ == "__main__":
    main()
