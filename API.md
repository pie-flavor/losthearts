# Lost Hearts

All API symbols are elements of the `LostHeartsAPI` table.

### `HeartType`

An enum of the kinds of heart state a player can have. The elements are None, Rotten, Black, Gold, Eternal, and Bone. This is a flags enum, so membership must be checked with `&`, not `==`.

### `index`

A function that takes an EntityPlayer and returns that player's (string) index into the mantle_states and soul_hearts table. If you are using IsaacScript, this function is identical to isaacscript-common's index function.

### `mantle_states`

A table of player index to what kind of heart the player has picked up. If a player isn't the Lost or hasn't picked up a heart, it's unspecified whether their entry is 0 or nil.
Again, checking a state must be with `state & flag ~= 0`, not `state == flag`.

### `soul_hearts`

A table of player index to how many soul hearts the player has picked up. If a player isn't the Lost or hasn't picked up a heart, it's unspecified whether their entry is 0 or nil.

### `set_mantle_state`

A function taking an EntityPlayer and a HeartType, which correctly sets the player's mantle state to that heart type. 
Use this instead of assigning directly to `mantle_states[idx]`, because depending on context this may combine states instead of replacing them.

This mod also assigns four new costumes to `NullItemID`: `ID_HOLYMANTLE_GREEN`, `ID_HOLYMANTLE_BLACK`, `ID_HOLYMANTLE_GOLD`, and `ID_HOLYMANTLE_GRAY`.
