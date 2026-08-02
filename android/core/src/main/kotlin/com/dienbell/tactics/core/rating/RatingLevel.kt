package com.dienbell.tactics.core.rating

/**
 * A 100-point rating band within the supported 1000–1999 range. Ratings outside
 * the range clamp to the nearest band. Equality is by lowerBound.
 */
class RatingLevel(rating: Int) {

    val lowerBound: Int = (rating / 100 * 100).coerceIn(MIN, MAX)

    val upperBound: Int get() = lowerBound + 100
    val rawValue: String get() = lowerBound.toString()
    val ratingRange: IntRange get() = lowerBound until upperBound

    override fun equals(other: Any?): Boolean = other is RatingLevel && other.lowerBound == lowerBound
    override fun hashCode(): Int = lowerBound
    override fun toString(): String = "RatingLevel($lowerBound)"

    companion object {
        private const val MIN = 1000
        private const val MAX = 1900
        private val BOUNDS = (MIN..MAX step 100).toSet()

        fun fromRawValue(value: String): RatingLevel? {
            val n = value.toIntOrNull() ?: return null
            return if (n in BOUNDS) RatingLevel(n) else null
        }
    }
}
