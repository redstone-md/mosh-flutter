use super::*;
use ::rand::{rngs::StdRng, SeedableRng};
use std::collections::HashSet;

#[test]
fn removals_are_bounded_distinct_and_exclude_the_sender() {
    for size in [1, 2, 3, 7] {
        let members: Vec<_> = (0..size).map(|i| (i * 4, vec![i as u8])).collect();
        for own_index in members.iter().map(|(index, _)| *index) {
            for seed in 0..64 {
                let mut rng = StdRng::seed_from_u64(seed);
                let targets = random_removal_targets(&members, own_index, &mut rng);
                assert_eq!(targets.is_empty(), size == 1);
                assert!(targets.len() <= (size - 1).min(5));
                assert!(!targets.contains(&LeafNodeIndex::new(own_index as u32)));
                assert_eq!(targets.iter().collect::<HashSet<_>>().len(), targets.len());
                assert!(targets.iter().all(|target| members
                    .iter()
                    .any(|(index, _)| { *target == LeafNodeIndex::new(*index as u32) })));
            }
        }
    }
}
