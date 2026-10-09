from test_cli import test_execute_supports_quoted_values_and_safe_parse_errors
from test_cli import test_repl_runs_complete_user_scenario
from test_store import test_delete_cleans_value_lru_and_ttl
from test_store import test_empty_value_overwrite_and_eviction_keep_memory_exact
from test_store import test_expiration_cleanup_handles_stale_heap_records
from test_store import test_get_refreshes_lru_before_eviction
from test_store import test_oversize_write_is_atomic_for_existing_key
from test_store import test_utf8_memory_and_overwrite_reset_ttl
from test_structures import test_hash_map_resizes_and_preserves_colliding_entries
from test_structures import test_linked_list_supports_constant_time_reordering
from test_structures import test_min_heap_orders_expirations_and_keys


def main() -> None:
    tests = [
        test_linked_list_supports_constant_time_reordering,
        test_hash_map_resizes_and_preserves_colliding_entries,
        test_min_heap_orders_expirations_and_keys,
        test_utf8_memory_and_overwrite_reset_ttl,
        test_get_refreshes_lru_before_eviction,
        test_oversize_write_is_atomic_for_existing_key,
        test_expiration_cleanup_handles_stale_heap_records,
        test_delete_cleans_value_lru_and_ttl,
        test_empty_value_overwrite_and_eviction_keep_memory_exact,
        test_execute_supports_quoted_values_and_safe_parse_errors,
        test_repl_runs_complete_user_scenario,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print(f"ALL TESTS PASSED ({len(tests)})")


if __name__ == "__main__":
    main()
