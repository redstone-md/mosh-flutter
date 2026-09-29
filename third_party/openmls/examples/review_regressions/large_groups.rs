use super::*;

#[test]
fn benchmark_cli_rejects_groups_without_a_second_member() {
    for size in ["0", "1", "invalid"] {
        assert!(Args::try_parse_from(["large-groups", "--groups", size]).is_err());
    }
    let args = Args::try_parse_from(["large-groups", "--groups", "2", "3"]).unwrap();
    assert_eq!(args.groups, Some(vec![2, 3]));
    assert!(Args::try_parse_from(["large-groups"])
        .unwrap()
        .groups
        .is_none());
}
