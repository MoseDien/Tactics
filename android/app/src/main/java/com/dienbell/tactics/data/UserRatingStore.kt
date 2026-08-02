package com.dienbell.tactics.data

import android.content.Context
import com.dienbell.tactics.core.rating.RatingLevel

/**
 * Persists the current rating + tier band. SharedPreferences replaces iOS
 * UserDefaults (the DataStore dep isn't available offline in this build env).
 */
class UserRatingStore(context: Context) {
    private val prefs = context.getSharedPreferences("dailytactics.rating", Context.MODE_PRIVATE)

    fun rating(): Int = prefs.getInt(KEY_RATING, INITIAL)

    fun level(): RatingLevel =
        RatingLevel.fromRawValue(prefs.getString(KEY_LEVEL, "") ?: "") ?: RatingLevel(rating())

    /** Applies an Elo delta, clamps to 400–3000, persists rating + tier, returns the new rating. */
    fun apply(delta: Int): Int {
        val updated = (rating() + delta).coerceIn(400, 3000)
        set(updated)
        return updated
    }

    fun set(rating: Int) {
        val clamped = rating.coerceIn(400, 3000)
        prefs.edit()
            .putInt(KEY_RATING, clamped)
            .putString(KEY_LEVEL, RatingLevel(clamped).rawValue)
            .apply()
    }

    fun reset() {
        prefs.edit().remove(KEY_RATING).remove(KEY_LEVEL).apply()
    }

    private companion object {
        const val KEY_RATING = "dailytactics.userRating"
        const val KEY_LEVEL = "dailytactics.ratingLevel"
        const val INITIAL = 1500
    }
}
