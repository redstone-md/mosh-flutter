use openmls::prelude::Lifetime;

#[test]
fn historical_time_is_scoped_nested_and_thread_local() {
    let expired = Lifetime::init(10, 20);
    assert!(!expired.is_valid());
    Lifetime::with_validation_time(15, || {
        assert!(expired.is_valid());
        for boundary in [10, 20, 30] {
            Lifetime::with_validation_time(boundary, || assert!(!expired.is_valid()));
            assert!(expired.is_valid());
        }
        std::thread::spawn(move || assert!(!expired.is_valid()))
            .join()
            .unwrap();
        assert!(!Lifetime::default().is_valid());
        assert!(std::panic::catch_unwind(|| {
            Lifetime::with_validation_time(30, || panic!("nested unwind"));
        })
        .is_err());
        assert!(expired.is_valid());
    });
    assert!(!expired.is_valid());
    assert!(Lifetime::default().is_valid());
    assert!(std::panic::catch_unwind(|| {
        Lifetime::with_validation_time(15, || panic!("outer unwind"));
    })
    .is_err());
    assert!(!expired.is_valid());
}
