package com.dienbell.tactics.data

import androidx.room.TypeConverter

/** Stores List<String> columns (moves, themes, openingTags) as a separated string.
 *  UCI moves and Lichess theme tags never contain the Unit Separator character. */
class Converters {
    @TypeConverter
    fun fromList(values: List<String>?): String? =
        values?.takeIf { it.isNotEmpty() }?.joinToString(SEPARATOR)

    @TypeConverter
    fun toList(value: String?): List<String>? =
        value?.takeIf { it.isNotEmpty() }?.split(SEPARATOR)

    private companion object { const val SEPARATOR = "" }
}
