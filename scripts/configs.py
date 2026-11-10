"""Map-generation configurations per game mode, mirroring GameWorld.prepareLevelStart.

    python configs.py > configs.json

Each config is one distinct map distribution; guild challenges that share an
archetype and identical generator settings share a batch. Archetype edits are
listed in the order the game applies them, with factors computed in float64
exactly as GDScript does, so int truncation matches.

game_mode holds the render/dkmode.gd options for room placement; cave_variants lists
"base" (no pets left to find) and, for Relic Hunt above small size, "nest" (pets still
unlockable, which adds the nest room).
"""
import json

N_DEFAULT = 3000
N_BIG = 1500

ASSIGNMENTS = {  # id: (title, archetype, goaltype, archetype-touching world modifiers)
    "showdown": ("Showdown", "assignment-default", "survive", []),
    "ironcontribution": ("Iron Contribution", "assignment-default", "property", ["nomonsters"]),
    "inversegravity": ("Upside Down", "assignment-default", "relic", []),
    "maze": ("Maze", "assignment-maze", "relic", []),
    "projectilehell": ("Projectile Hell", "assignment-default", "relic", []),
    "denseiron": ("Dense Iron", "assignment-dense-iron", "relic", []),
    "bigmapsparseresources": ("Barren Lands", "assignment-softrock-sparseresources", "relic", []),
    "weapondefect": ("Defective Weapon", "assignment-default", "relic", []),
    "heavyhitters": ("Heavy Hitters", "assignment-default", "relic", []),
    "superhardrockwithholes": ("Swiss Cheese", "assignment-hardrock-manyholes", "relic", []),
    "weakcarry": ("Logistical Problem", "assignment-default", "relic", []),
    "weakwalls": ("High Risk", "assignment-default", "relic", []),
    "monstermasses": ("Monster Masses", "assignment-default", "relic", []),
    "rareiron": ("Iron Shortage", "assignment-rare-iron", "relic", []),
    "weakmining": ("Mining Problem", "assignment-default", "relic", []),
    "cobaltcontribution": ("Cobalt Contribution", "assignment-default", "property", []),
    "minorvision": ("Darkness", "assignment-minorvision", "relic", []),
    "acidrain": ("Acid Rain", "assignment-acidrain", "relic", []),
    "treefarm": ("Tree Farm", "assignment-tree-farm", "relic", []),
    "megacreeps": ("Survival of the Fittest", "assignment-default", "relic", []),
    "instagip": ("Brutal Monsters", "assignment-default", "relic", []),
    "harmfuliron": ("Hazardous Iron", "assignment-default", "relic", []),
    "unpredictable": ("Broken Comms", "assignment-default", "relic", []),
    "emergency": ("Emergency", "assignment-default", "property", []),
    "logistics": ("Logistical Nightmare", "assignment-logistics", "property", ["nomonsters"]),
}

MODIFIER_OPS = {  # upgrades.yaml worldmodifier<id>, archetype.* property changes only
    "nomonsters": ["cobalt_rate*=0.0"],
    "maze": ["max_tile_count_deviation+=0.05", "viability_large_noise_strength+=420",
             "viability_small_noise_strength=0",
             "viability_large_noise=res://content/map/generation/noises/viability_maze.tres"],
    "domesupplements": ["powercore_first_depth*=0.8", "powercore_depth_step*=0.65", "powercores*=3"],
}
MODIFIER_TITLES = {"maze": "Maze", "domesupplements": "Triple Supplements"}


def multiplayer_ops(n_players: int) -> list:
    mod = min(max((n_players - 1) * 0.15, 0.0), 0.5)
    return [f"max_tile_count_deviation+={mod!r}", f"tileCount*={1.0 + mod!r}",
            f"width*={1.0 + mod * 0.6!r}", f"depth*={1.0 + mod * 1.2!r}",
            f"first_biome_size*={1.0 + mod * 2.0!r}", f"biome_max_size*={1.0 + mod!r}",
            f"biome_size_multiplier*={1.0 + mod * 0.5!r}", f"biome_size_addition*={1.0 + mod!r}"]


COOP_OPS = ["depth*=1.4", "width*=1.3", "gadget_first_depth*=1.5", "gadget_depth_step*=1.8", "water_rate*=0.9"]


def configs() -> list:
    out = []
    groups = {}
    for aid, (title, arch, goal, mods) in ASSIGNMENTS.items():
        ops = [op for m in mods for op in MODIFIER_OPS[m]] + [f"relics={int(goal == 'relic')}"]
        groups.setdefault((arch, tuple(ops)), []).append((aid, title))
    for (arch, ops), members in groups.items():
        suffix = "".join(["_norelic" if "relics=0" in ops else "", "_nocobalt" if "cobalt_rate*=0.0" in ops else ""])
        out.append({"tag": f"guild_{arch.removeprefix('assignment-')}{suffix}", "group": "Guild assignment",
                    "archetype": arch, "ops": list(ops), "n": N_DEFAULT,
                    "challenges": [{"id": a, "title": t} for a, t in members],
                    "game_mode": {"mode": "assignments", "assignment": members[0][0]},
                    "cave_variants": ["base"]})

    for size in ["small", "medium", "large", "huge"]:
        for mod in [None, "maze", "domesupplements"]:
            ops = MODIFIER_OPS[mod] if mod else []
            out.append({"tag": f"relichunt_{size}" + (f"_{mod}" if mod else ""), "group": "Relic Hunt",
                        "archetype": f"regular-{size}", "ops": ops, "n": N_DEFAULT,
                        "size": size, "modifier": MODIFIER_TITLES.get(mod),
                        "game_mode": {"mode": "relichunt", "mapsize": f"regular-{size}",
                                      "modifiers": f"worldmodifier{mod}" if mod else ""},
                        "cave_variants": ["base"] + (["nest"] if size != "small" else [])})
    for size in ["small", "medium", "large", "huge"]:
        out.append({"tag": f"coop2_{size}", "group": "Co-op (2 players)", "archetype": f"regular-{size}",
                    "ops": multiplayer_ops(2) + COOP_OPS, "n": N_DEFAULT, "size": size,
                    "game_mode": {"mode": "coop", "mapsize": f"regular-{size}"},
                    "cave_variants": ["base"]})
    out.append({"tag": "prestige_10k", "group": "Prestige", "archetype": "prestige-10k", "ops": [], "n": N_BIG,
                "game_mode": {"mode": "prestige"}, "cave_variants": ["base"]})
    out.append({"tag": "prestige_20k", "group": "Prestige", "archetype": "prestige-20k", "ops": [], "n": N_BIG,
                "game_mode": {"mode": "prestige"}, "cave_variants": ["base"]})
    return out


if __name__ == "__main__":
    print(json.dumps(configs(), indent=1))
