# Bagnon PinSell

A **[Bagnon](https://www.wowace.com/projects/bagnon) plugin for WotLK 3.3.5a**
that gives bag slots persistent roles, so your bag layout survives the
auto-sort button — plus grey-item auto-selling at vendors.

Bagnon's sort button reorganizes everything, every time. PinSell lets you
carve out exceptions:

- **Pin an item to a slot** — alt-right-click an occupied slot (star marker).
  Auto-sort will never move it, and if the item ends up anywhere else in your
  bags (bought more, looted, misplaced), it is automatically moved back to its
  home slot.
- **Reserve slots for quest items** — alt-right-click an *empty* slot
  (**!** marker). New quest items are automatically pulled into reserved
  slots, non-quest loot that lands there is evicted, and auto-sort leaves the
  slots alone.
- **Auto-sell greys** — opening a vendor sells all poor-quality items, except
  anything sitting in a pinned or reserved slot. Reports the total earned.

Alt-right-click a marked slot again to clear its role. Pins and reservations
are per-character and apply to the backpack bags (0–4).

## Install

Requires **Bagnon** (written against 2.13.3 for 3.3.5). Copy the
`Bagnon_PinSell` folder into `Interface/AddOns/` and restart the client.

## Commands

| Command | Effect |
|---|---|
| `/bps` | Toggle grey auto-sell on/off |
| `/bps list` | Show pinned and quest-reserved slots |

## How it works

- Bagnon's sort is fully client-side (`Bagnon/utility/sorting.lua`). PinSell
  wraps `Sorting:GetSpaces()` and filters protected slots out of the sorter's
  workspace, so they can't be used as a source *or* a destination.
- Item returns and quest-slot filling run through an async move queue that
  waits on server item locks, fires ~0.6 s after bag activity settles, and
  stands down in combat — the same constraints Bagnon's own sorter obeys.
- Quest items are detected via `GetContainerItemQuestInfo` (quest-class items
  and quest starters).
- Clicks are intercepted per item button (the default handler would *use* the
  item on alt-right-click); everything hooks Bagnon from the outside, so no
  Bagnon files are modified and the plugin survives Bagnon updates.

Written for and tested on [Ascension WoW](https://ascension.gg) (Conquest of
Azeroth); works on any 3.3.5a client running Bagnon.

## Acknowledgements

- **Tuller** — author of Bagnon, whose clean class structure (`ItemSlot`,
  `Sorting`) makes hooking from a plugin this painless.
- The Bagnon sub-addon ecosystem (Bagnon_Config, Bagnon_Forever, …) for the
  plugin pattern this follows.

## License

MIT (see `LICENSE`). Bagnon itself is the work of Tuller and is not included
in this repository.
