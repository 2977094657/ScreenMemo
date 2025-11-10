package com.fqyw.screen_memo.memory.model

/**
 * 标签类别枚举，用于区分不同类型的用户画像线索。
 *
 * - IDENTITY：身份信息，如姓名、昵称、职业等。
 * - RELATIONSHIP：与他人的关系，例如家庭成员、同事、好友。
 * - INTEREST：兴趣爱好，如喜欢的音乐、电影、运动等。
 * - BEHAVIOR：行为习惯，例如常用设备、作息习惯。
 * - PREFERENCE：偏好设置，如界面风格、功能喜好。
 * - OTHER：无法归类但确认为用户相关的信息。
 */
enum class TagCategory(val storageValue: String) {
    IDENTITY("identity"),
    RELATIONSHIP("relationship"),
    INTEREST("interest"),
    BEHAVIOR("behavior"),
    PREFERENCE("preference"),
    OTHER("other");

    companion object {
        fun fromStorageValue(value: String?): TagCategory {
            if (value.isNullOrBlank()) return OTHER
            return values().firstOrNull { it.storageValue == value } ?: OTHER
        }
    }
}

