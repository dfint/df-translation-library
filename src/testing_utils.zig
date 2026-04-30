/// Utility structure factory for test parametrization
pub fn TestDataEntry(comptime X: type, comptime Y: type) type {
    return struct {
        input: X,
        expected: Y,
    };
}
