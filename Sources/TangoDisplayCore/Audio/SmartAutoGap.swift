public enum SmartAutoGap {
    public static func injectedDuration(
        target: Double,
        trailing: Double,
        leading: Double
    ) -> Double {
        guard target.isFinite, target > 0 else { return 0 }

        let safeTrailing = trailing.isFinite && trailing > 0 ? trailing : 0
        let safeLeading = leading.isFinite && leading > 0 ? leading : 0
        return max(0, target - safeTrailing - safeLeading)
    }
}
