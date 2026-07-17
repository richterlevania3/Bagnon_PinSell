# Bagnon PinSell

A **[Bagnon](https://www.wowace.com/projects/bagnon) plugin for WotLK 3.3.5a**
that gives bag slots persistent roles, so your bag layout survives the
auto-sort button — plus grey-item auto-selling at vendors.

This repository ships the **complete, working Bagnon suite** (Bagnon 2.13.3
and its sub-addons, unmodified) alongside the plugin, so a fresh WoW install
is one copy-paste:

| Folder | What it is |
|---|---|
| `Bagnon_PinSell` | This plugin (slot pinning, quest slots, auto-sell) |
| `Bagnon` | Tuller's Bagnon 2.13.3 for 3.3.5 (unmodified) |
| `Bagnon_Config` | Bagnon options UI |
| `Bagnon_Forever` | Cross-character item caching |
| `Bagnon_GuildBank`, `Bagnon_Tooltips`, `Bagnon_VoidStorage` | Stock Bagnon sub-addons |

Bagnon's sort button reorganizes everything, every time. PinSell lets you
carve out exceptions:

- **Pin an item to a slot** — ctrl-right-click an occupied slot (star marker).
  Sorting will never move it.
- **Reserve slots for quest items** — ctrl-right-click an *empty* slot
  (**!** marker). Sorting won't take the slot or dump items into it.
- **Auto-sell greys** — opening a vendor sells all poor-quality items, except
  anything sitting in a pinned or reserved slot. Reports the total earned.

Ctrl-right-click a marked slot again to clear its role. Pins and reservations
are per-character and apply to the backpack bags (0–4). PinSell never moves
items on its own — your bags only change when *you* click clean-up. When you
do, before the normal sort runs:

- loose quest items are pulled **into** your quest-reserved slots (evicting
  any non-quest squatter by swap);
- with no quest items left to place, non-quest items still sitting in
  reserved slots are moved **out** to a free slot (they stay put if your bags
  are full).

PinSell also guards against a stock Bagnon sorter bug: items whose reported
stack size disagrees with the server (common with custom-server items) make
the sort loop forever. PinSell detects the repeating bag state and stops the
sort with a chat notice instead.

## Install

Copy **all** the addon folders from this repository into `Interface/AddOns/`
and restart the client. (If you already run Bagnon, copying just
`Bagnon_PinSell` works too — it's written against Bagnon 2.13.3.)

## Commands

| Command | Effect |
|---|---|
| `/bps` | Toggle grey auto-sell on/off |
| `/bps list` | Show pinned and quest-reserved slots |

## How it works

- Bagnon's sort is fully client-side (`Bagnon/utility/sorting.lua`). PinSell
  wraps `Sorting:GetSpaces()` and filters protected slots out of the sorter's
  workspace, so they can't be used as a source *or* a destination.
- Clicks are intercepted per item button (the default handler would *use* the
  item on ctrl-right-click); everything hooks Bagnon from the outside, so no
  Bagnon files are modified and the plugin survives Bagnon updates.

Written for and tested on [Ascension WoW](https://ascension.gg) (Conquest of
Azeroth); works on any 3.3.5a client running Bagnon.

## Acknowledgements

- **Tuller** — author of Bagnon, whose clean class structure (`ItemSlot`,
  `Sorting`) makes hooking from a plugin this painless.
- The Bagnon sub-addon ecosystem (Bagnon_Config, Bagnon_Forever, …) for the
  plugin pattern this follows.

## License

The `Bagnon_PinSell` plugin is MIT (see `LICENSE`). Bagnon and its
sub-addons remain the work of Tuller and their respective contributors —
they are included here unmodified purely for install convenience, and all
rights stay with their authors.
