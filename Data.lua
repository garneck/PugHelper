--[[-------------------------------------------------------------------------
    PUG Helper - Data.lua
---------------------------------------------------------------------------
    This is the file you will edit most. Everything below is plain text.

    HOW TOKENS WORK
      Any {TOKEN} inside a message line is replaced with the name you set
      in the "Set Names" panel (or via /pug name TOKEN Yourname).
      If a token has no name set, the {TOKEN} text is left visible so you
      know that slot still needs filling.

    HOW TO ADD / CHANGE MESSAGES
      Each raid is a { } block with a list of "sections".
      Each section has a title and a list of "lines".
      A line is just a string in "double quotes" ending with a comma.
      Add, remove, or rewrite lines freely. Keep the commas.

    TIP: lines longer than ~240 characters are split into multiple chat
    messages automatically, but shorter punchy callouts read better.
---------------------------------------------------------------------------]]

-- Role tokens shown in the "Set Names" panel. key = the {TOKEN}; label = display name.
-- IMPORTANT: keys must be letters/numbers only (no spaces, dashes, or underscores).
-- Substitution matches {%w+}, so a key like "INT_1" would never get filled in.
PugHelperRoles = {
    { key = "MT",   label = "Main Tank" },
    { key = "OT",   label = "Off Tank" },
    { key = "OT2",  label = "Off Tank 2" },
    { key = "OT3",  label = "Off Tank 3" },
    { key = "H1",   label = "Healer 1" },
    { key = "H2",   label = "Healer 2" },
    { key = "H3",   label = "Healer 3" },
    { key = "H4",   label = "Healer 4" },
    { key = "H5",   label = "Healer 5" },
    { key = "CC1",  label = "Crowd Control 1" },
    { key = "CC2",  label = "Crowd Control 2" },
    { key = "CC3",  label = "Crowd Control 3" },
    { key = "INT1", label = "Interrupt 1" },
    { key = "INT2", label = "Interrupt 2" },
    { key = "DISP", label = "Dispel / Decurse" },
    { key = "BL",   label = "Bloodlust / Hero" },
}

PugHelperRaids = {

    ----------------------------------------------------------------------
    {
        name = "Karazhan",
        note = "10-player | Phase 1 (live)",
        sections = {
            { title = "Trash", lines = {
                "Karazhan trash - mark Skull = kill first, X = second. CC the casters/humanoids; don't break CC with cleaves or AoE.",
                "Mana up before each pull. Tanks grab adds and wait for CC before DPS opens. Watch the patrols on the stairs.",
            }},
            { title = "Attumen the Huntsman", lines = {
                "Attumen - tank Midnight first; Attumen joins ~95%. At 25% they merge into one mounted boss. {OT} grab Attumen when he appears.",
                "Spread out for Charge. Melee stay behind, avoid the frontal cleave, and move out of the Charge target's path.",
            }},
            { title = "Moroes", lines = {
                "Moroes - CC his adds: {CC1} {CC2} {CC3} hold your marks. {MT} tank Moroes facing away. Vanish = he restealths and Garrotes a random target.",
                "Healers watch Garrote (heavy bleed) and Gouge on the tank - {OT} taunt during Gouge. Kill Moroes, then clean up the CC'd guests.",
            }},
            { title = "Maiden of Virtue", lines = {
                "Maiden - ranged & healers stay OUT of melee range (Holy Ground silences + damages). Stack the melee on her.",
                "Repentance = raid-wide stun, breaks on damage, so top everyone before it ends. {DISP} cleanse where you can.",
            }},
            { title = "Opera Event (random)", lines = {
                "Opera Oz: kill Dorothee then Tito, Roar, Strawman, Tinhead, then Crone (run from her Cyclone).",
                "Opera Wolf: the 'Red Riding Hood' target must KITE the wolf - don't let it catch you.",
                "Opera Romulo & Julianne: both must die within ~10s of each other or they revive. Watch the poison and charges.",
            }},
            { title = "The Curator", lines = {
                "Curator - kill Astral Flares fast (they nuke and stack up). {OT} soak Hateful Bolt (hits 2nd on threat in melee).",
                "Every 3rd flare he Evocates: stops casting and takes +200% damage. BURN him in that window. {BL} here if assigned.",
            }},
            { title = "Terestian Illhoof", lines = {
                "Illhoof - kill Kil'rek (the imp) for the vulnerability debuff; it respawns, so repeat. AoE the imp swarms down fast.",
                "Sacrifice = a player gets chained (Demon Chains). Kill the chains immediately to free them - it drains their HP and heals the boss.",
            }},
            { title = "Shade of Aran", lines = {
                "Aran - FLAME WREATH: do NOT move when you have it (you and others die). Blizzard: move out. Arcane Explosion: run AWAY from him.",
                "At 40% he Conjures water, drinks, then Pyroblasts - {INT1} interrupt the drink or burst him down. Spread to avoid Chains+Pyroblast combos.",
            }},
            { title = "Netherspite", lines = {
                "Netherspite - Beam phase: RED beam = tank/threat, GREEN = heal, BLUE = dps/mana. Rotate players through beams; don't let one hold a beam too long.",
                "Tank him near the portals facing away. Banish phase: he leaves - reposition and heal up, then repeat beam -> banish.",
            }},
            { title = "Chess Event", lines = {
                "Chess - right-click your piece to move/attack. Focus the enemy king's healers and casters, use Medivh's fire on weak pieces. Steady pressure wins.",
            }},
            { title = "Prince Malchezaar", lines = {
                "Prince P1 - Enfeeble drops you to 1 HP (DON'T panic-heal, it expires). Shadow Nova = AoE, be ready. P2 (60%): Infernals rain - MOVE out of their fire.",
                "P3 (30%): he drops aggro and dual-wields Axes (huge melee) plus more infernals. Spread, keep moving, blow cooldowns. {MT} re-pick him after axes.",
            }},
            { title = "Nightbane (optional)", lines = {
                "Nightbane ground phase - tank faces away; avoid Cleave and Bellowing Roar (fear). Charred Earth: move out of the fire on the floor.",
                "Air phase (75/50/25%): he flies, rains Bone + spawns skeletons. AoE/kill skeletons, dodge bone patches, then he lands and repeats.",
            }},
            { title = "Assignments", lines = {
                "TANKS: {MT} = main tank / boss. {OT} = off-tank / adds. {OT2} backup.",
                "HEALS: {H1} on {MT}, {H2} on {OT}, {H3} raid + dispels. Call out if you go OOM.",
                "CC: {CC1} {CC2} {CC3} - mark your targets and re-CC. Interrupts: {INT1} {INT2}. Bloodlust/Hero: {BL}.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "Gruul's Lair",
        note = "25-player | Phase 1 (live)",
        sections = {
            { title = "Trash", lines = {
                "Gruul trash - clear the elite groups carefully, mark a kill order, CC where possible. Watch the big Gronn patrol before Maulgar.",
            }},
            { title = "High King Maulgar (council)", lines = {
                "Maulgar - 5 bosses, ONE tank each: {MT} Maulgar, {OT} Krosh (warlock ideal), {OT2} Olm, hunter kites Kiggler, {OT3} Blindeye.",
                "Kill order: Blindeye (priest, stops heals) -> Olm (stops imps) -> Kiggler -> Krosh -> Maulgar. AoE Olm's imps. Avoid Krosh's Blast Wave.",
                "Krosh casts Greater Polymorph and has a Spellshield - interrupt/Spell Lock it. Maulgar Whirlwinds + Mighty Blow; melee back off on WW.",
            }},
            { title = "Gruul the Dragonkiller", lines = {
                "Gruul - Growth stacks forever (bigger + harder hits), so BURN before it's lethal. {OT} soak Hurtful Strike (2nd on threat).",
                "Ground Slam -> Shatter: everyone is tossed, then Shatter damages by proximity - SPREAD OUT so you don't chain-kill each other. Move out of Cave In.",
            }},
            { title = "Assignments", lines = {
                "MAULGAR TANKS: {MT}=Maulgar, {OT}=Krosh, {OT2}=Olm, {OT3}=Blindeye, hunter kites Kiggler.",
                "HEALS: {H1} {H2} on Maulgar tank, {H3} Krosh/Olm tanks, {H4} raid + Kiggler kiter, {H5} flex. {DISP} dispel Polymorph & Death Coil.",
                "GRUUL: stack for threat, SPREAD on Ground Slam for Shatter. {BL} Bloodlust on pull or around 50%.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "Magtheridon's Lair",
        note = "25-player | Phase 1 (live)",
        sections = {
            { title = "Phase 1 - Channelers", lines = {
                "Mag has no trash - the 5 Hellfire Channelers ARE Phase 1. Assign a tank/spot to each and kill them while managing Magtheridon.",
                "Channelers Shadow Bolt Volley and heal each other ({DISP}/interrupt Dark Mending). Tank the Burning Abyssal adds they summon.",
            }},
            { title = "Cubes (THE mechanic)", lines = {
                "CUBES: when Mag channels Blast Nova, 5 players click the Manticron Cubes AT THE SAME TIME to interrupt it. Miss it and the raid wipes.",
                "Assign your 5 cube clickers now. Click ON Blast Nova, together. Clicking gives a debuff - rotate so the same person isn't always cubing.",
            }},
            { title = "Phase 2 - Magtheridon", lines = {
                "P2 (Mag freed ~30s after channelers die): Cleave on tank, keep clicking cubes on Blast Nova, move out of falling Debris, watch Quake knockback.",
            }},
            { title = "Assignments", lines = {
                "CHANNELER TANKS: split the 5 among {MT} {OT} {OT2} {OT3} + 1 more. Call the 5th in voice.",
                "CUBE CLICKERS (5): assign 5 names - click together on Blast Nova. {DISP} interrupt Dark Mending heals.",
                "HEALS: spread across channeler tanks in P1, then stack on {MT} for P2. {BL} when Mag is active in P2.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "The Eye (Tempest Keep)",
        note = "25-player | Phase 2 (live)",
        sections = {
            { title = "Trash", lines = {
                "TK trash - patrol packs of Crystalcore / phoenix-hawk mobs. CC casters, mark kill order, clear to each boss and mind the reset lines.",
            }},
            { title = "Al'ar", lines = {
                "Al'ar P1 - tank on the platforms; it moves between perches. Avoid Flame Quills (big AoE - spread/LOS). P2: it dies once and rebirths on the floor.",
                "P2: chase it, kill Ember of Al'ar adds, avoid Melt Armor on tank and the flame patches. It Dive Bombs after a meteor - move out.",
            }},
            { title = "Void Reaver", lines = {
                "Void Reaver ('Loot Reaver') - easy. SPREAD for Arcane Orbs (random target, big splash - don't clump). {OT} soak Pounding. Mostly just don't stack.",
            }},
            { title = "High Astromancer Solarian", lines = {
                "Solarian - Wrath of the Astromancer: bomb on a player, RUN from the raid before it blows (it also teleports you). She splits and blinks with adds - kill adds.",
                "At ~20% she becomes a giant Voidwalker (Solarian Prime) - big melee, just tank and burn. {DISP} track/dispel the bomb target.",
            }},
            { title = "Kael'thas Sunstrider", lines = {
                "Kael - 5 phases. P1: kill his 4 Advisors one at a time. P2: 7 weapons spawn - tank/kill them (he uses them). P3: Advisors revive, kill again.",
                "P4: Kael active - Fireball, Flamestrike (move), Mind Control (CC/heal through), Pyroblast (interrupt/LOS). P5: Gravity Lapse - everyone floats, dodge orbs, fly to him.",
            }},
            { title = "Assignments", lines = {
                "TANKS: {MT}=boss, {OT}=adds/2nd, {OT2} weapons (Kael). HEALS: {H1} {H2} tank, {H3} {H4} raid, {H5} flex.",
                "Solarian/Kael: {DISP} on the bomb and Mind Control. Spread for orbs/bombs. {BL} on the final burn phase.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "Serpentshrine Cavern",
        note = "25-player | Phase 2 (live)",
        sections = {
            { title = "Trash", lines = {
                "SSC trash - Naga + Fish Tide packs. CC casters (sheep/trap/shackle), mark Skull/X, watch the Coilfang patrols and the bridges.",
            }},
            { title = "Hydross the Unstable", lines = {
                "Hydross - TANK SWAP on aura change: Nature near his spot, Frost across the line. Need a Nature-resist AND a Frost-resist tank ({MT}/{OT}).",
                "Each transition spawns 4 elementals (offtank/AoE them). Don't cross the line carelessly - it flips his element and resets the mark stacks.",
            }},
            { title = "The Lurker Below", lines = {
                "Lurker - fish him up from the center pool. Spout = rotating water jet: get BEHIND a pillar / break LOS or you're knocked into the water.",
                "Submerge phase: he dives, adds spawn on the platforms (tank & kill), then he resurfaces. Repeat.",
            }},
            { title = "Leotheras the Blind", lines = {
                "Leotheras - Whirlwind (Human) phase: melee back OFF. Demon phase needs a Warlock tank. Inner Demons: kill YOUR OWN demon or you get Mind Controlled.",
                "At 15% everyone gets an Inner Demon at once - kill yours fast. Spread for Whirlwind, {DISP} dispel Insidious Whisper.",
            }},
            { title = "Fathom-Lord Karathress", lines = {
                "Karathress - kill the 3 advisors first (each grants him a power): Sharkkra (heals/totems), Tidalvess (poison/totems), Caribdis (waterbolt/cyclone).",
                "Assign tank + kill order for the adds, kill totems, then burn Karathress. He gets stronger per advisor alive - don't let it drag.",
            }},
            { title = "Morogrim Tidewalker", lines = {
                "Morogrim - Murloc adds spawn in waves: AoE them down FAST or healers get overwhelmed. Watery Grave: random players teleported to water - heal/free them.",
                "Tidal Wave: frontal knockback + slow - face him AWAY from raid. {OT} taunt-swap if needed.",
            }},
            { title = "Lady Vashj", lines = {
                "Vashj P1 - tank & burn to 70%. P2: SHIELD up (immune). Kill Tainted Elementals, grab the Tainted Cores they drop, RELAY cores to the 4 generators to drop the shield.",
                "P2 also: Striders (kite/kill), Naga, Toxic Spores. P3: shield down, burn - Static Charge (spread), Forked Lightning, Entangle. {BL} in P3.",
            }},
            { title = "Assignments", lines = {
                "TANKS: {MT} boss, {OT} adds, {OT2}/{OT3} resist or 2nd-add tanks. Hydross: nature-res {MT}, frost-res {OT}.",
                "HEALS: {H1} {H2} main tank, {H3} offtank/adds, {H4} {H5} raid + dispels. {DISP} on poisons/whispers.",
                "Vashj P2: CORE RUNNERS relay Tainted Cores to the generators - assign in voice. {BL} on Vashj P3 / Lurker / burn windows.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "Battle for Mount Hyjal",
        note = "25-player | Phase 3 (not yet live - starter notes)",
        sections = {
            { title = "Trash / Waves", lines = {
                "Hyjal - wave defense at each base. Ghouls, abominations, banshees, necromancers pour in: AoE, focus casters, protect the NPC base (Jaina/Thrall).",
            }},
            { title = "Rage Winterchill", lines = {
                "Rage Winterchill - Death & Decay (move out), Frost Nova roots (have an out), Icebolt freezes a random player (heal them), Frostbolt on tank.",
            }},
            { title = "Anetheron", lines = {
                "Anetheron - Carrion Swarm (cone, cuts healing - face AWAY from raid), Sleep (dispel), Inferno: an Infernal drops with pulsing fire - move away / tank it off.",
            }},
            { title = "Kaz'rogal", lines = {
                "Kaz'rogal - Mark of Kaz'rogal drains your mana then EXPLODES at 0 (chain AoE). Mana classes burn mana down early. War Stomp + Cripple on melee.",
            }},
            { title = "Azgalor", lines = {
                "Azgalor - Mark like Doom: when it expires it spawns a Lesser Doomguard - {DISP} dispel/pass it, kill the Doomguards. Rain of Fire (move), Howl silences melee.",
            }},
            { title = "Archimonde", lines = {
                "Archimonde - everyone needs Tears of the Goddess (anti-fall). Air Burst tosses you up - use the Tear to survive landing. DOOMFIRE chases - RUN from it, don't drag it through raid.",
                "Grip of the Legion (dispel), Finger of Death (don't be alone at range when flagged). Spread, watch Doomfire, dispel fast. {DISP} {BL} ready.",
            }},
            { title = "Assignments", lines = {
                "WAVES: {MT} {OT} hold the chokepoint, ranged focus casters/necromancers, AoE the swarms. Save cooldowns for boss waves.",
                "BOSSES: {H1} {H2} tank, {H3} {H4} raid, {H5} flex. {DISP} dispel Marks/Doom/Sleep/Grip. {BL} on each boss burn.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "Black Temple",
        note = "25-player | Phase 3 (not yet live - starter notes)",
        sections = {
            { title = "Trash", lines = {
                "BT trash - long packs, CC + mark kill order, watch patrols. Several gauntlets; pull carefully and mana between packs.",
            }},
            { title = "High Warlord Naj'entus", lines = {
                "Naj'entus - pull the Impaling Spine off the ground while his shield is up to break it, then USE a spine on players hit by Impaling Spine to free them. Shield = burst window.",
            }},
            { title = "Supremus", lines = {
                "Supremus - Phase A: tank & spank, {OT} soak Hurtful Strike. Phase B: he chases a random player and Volcanic Geysers erupt - KITE him, everyone avoid the eruptions.",
            }},
            { title = "Shade of Akama", lines = {
                "Shade of Akama - kill the Channelers holding Akama, then the waves of adds (Sorcerers/Defenders). Once channelers die the Shade activates - tank & burn while adds continue.",
            }},
            { title = "Teron Gorefiend", lines = {
                "Teron - Shadow of Death: a player DIES and becomes a Ghost. As a ghost you MUST use the ghost abilities to kill the Shadowy Constructs, or they wipe the raid. Practice the ghost role.",
            }},
            { title = "Gurtogg Bloodboil", lines = {
                "Gurtogg - Bloodboil stacks (hits lowest-threat players), Acidic Wound on tank. FEL RAGE fixates a random player and buffs them - they tank him ~30s, heal them HARD, then back to {MT}.",
            }},
            { title = "Reliquary of Souls", lines = {
                "Reliquary - 3 Essences in sequence. Suffering: DPS race. Desire: NO outside healing works - use the boss aura to heal/burn. Anger: Soul Scream/Spite - burn fast.",
            }},
            { title = "Mother Shahraz", lines = {
                "Mother Shahraz - Fatal Attraction teleports 3 players together; they take damage if near each other, so SPREAD OUT always. Saber Lash splits between stacked tanks ({MT} {OT} {OT2} stack).",
            }},
            { title = "Illidari Council", lines = {
                "Illidari Council - 4 bosses share a health pool; spread damage and kill ~together. One tank each. Interrupt Gathios (pally heals), Zerevor (mage AoE), Malande (priest heals); watch Veras (rogue) poison/vanish.",
            }},
            { title = "Illidan Stormrage", lines = {
                "Illidan P1 - tank & spank, Parasitic Shadowfiend (spread, dispel), Flame Crash (move). P2: he flies & drops Flames of Azzinoth - 2 elementals, ONE tank each, kite through Blue Flame, don't overlap auras.",
                "P3: back to melee + Shadow Prison (don't move/take damage). P4: Demon form - Shadow Blast + demon adds (kill fast). Long fight - assign Glaive tanks and a demon kill team.",
            }},
            { title = "Assignments", lines = {
                "TANKS: {MT} boss, {OT} {OT2} {OT3} for Bloodboil swaps / Council / Glaives. Stack for Shahraz Saber Lash.",
                "HEALS: {H1} {H2} main tank, {H3} Fel Rage / swap target (heal HARD), {H4} {H5} raid + dispels. {DISP} on Parasitic/Bloodboil/Sleep.",
                "SPECIAL: Teron ghost team, Naj'entus spine pullers, Glaive tanks on Illidan - assign in voice. {BL} on burn phases.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "Zul'Aman",
        note = "10-player | Phase 3.5 (not yet live - starter notes)",
        sections = {
            { title = "Trash", lines = {
                "ZA trash - fast packs with many casters/healers: interrupt & focus them. If doing the TIMED run for chests, don't over-pull - keep moving.",
            }},
            { title = "Akil'zon (Eagle)", lines = {
                "Akil'zon - Electrical Storm lifts a player in a cloud; everyone else STACK under them to share the damage, then spread for Static Disruption. Gust of Wind knockback. Watch Eagle adds.",
            }},
            { title = "Nalorakk (Bear)", lines = {
                "Nalorakk - TANK SWAP on Brutal Swipe / Lacerate stacks (swap ~3 stacks). Surge charges a ranged player - face him away, melee stay behind. Adds on the way up.",
            }},
            { title = "Jan'alai (Dragonhawk)", lines = {
                "Jan'alai - hatchers run to the egg walls; let a FEW eggs hatch and AoE the hatchlings, but kill hatchers to control it. Avoid Flame Breath lanes and Fire Bombs. At 35% all eggs hatch.",
            }},
            { title = "Halazzi (Lynx)", lines = {
                "Halazzi - splits into Halazzi + a Lynx Spirit (tank the lynx separately), then they merge. Kill the Corrupted Totem fast. Saber Lash splits on stacked tanks. Interrupt his shocks.",
            }},
            { title = "Hex Lord Malacrass", lines = {
                "Hex Lord - kill his 4 captured adds (assign CC + kill order). He copies a player's class abilities (Drain Power). Spirit Bolts (AoE), Siphon Soul. Interrupt heals, dispel.",
            }},
            { title = "Zul'jin", lines = {
                "Zul'jin - 5 phases, each an animal aspect: P1 Troll (Grievous Throw - heal to full to clear), P2 Lynx (heavy melee on the target), P3 Eagle (Pillar of fire - move; Cyclone), P4 Bear (Creeping Paralysis - dispel), P5 Dragonhawk (Flame Whirl/Breath - fire everywhere, spread & burn).",
            }},
            { title = "Assignments", lines = {
                "TANKS: {MT} boss, {OT} adds / swaps (Nalorakk, Halazzi lynx, Hex Lord adds). HEALS: {H1} {H2} tank, {H3} {H4} raid, {H5} flex.",
                "Akil'zon: STACK on the storm target. {DISP} dispel Paralysis/Grievous. {BL} on Zul'jin P5 or timed-run burns.",
            }},
        },
    },

    ----------------------------------------------------------------------
    {
        name = "Sunwell Plateau",
        note = "25-player | Phase 4 (not yet live - starter notes)",
        sections = {
            { title = "Trash", lines = {
                "Sunwell trash - very dangerous packs (Dawnblade/Sunblade casters, Wretched). CC + interrupt heavily, mark kill order, mana between pulls. Don't chain-pull.",
            }},
            { title = "Kalecgos", lines = {
                "Kalecgos - Spectral Blast teleports players to the Spectral Realm to fight Sathrovarr; DPS him there while others DPS the dragon outside - keep BOTH at similar % (damage transfers). Dispel Wild Magic, watch Arcane Buffet.",
            }},
            { title = "Brutallus", lines = {
                "Brutallus - pure DPS/heal check. Burn (stacking fire debuff, ramps - healers heal through). Meteor Slash: frontal that SPLITS between players hit + stacking debuff - two groups soak alternately. Beat the 6-min enrage.",
            }},
            { title = "Felmyst", lines = {
                "Felmyst - Ground: Gas Clouds (move out), Encapsulate (run from the green sphere). Air: she breathes Fog of Corruption that MIND CONTROLS - run the fog away from raid. Corrosion on tank.",
            }},
            { title = "Eredar Twins", lines = {
                "Eredar Twins - Sacrolash (Shadow) + Alythess (Fire), tank APART. Shadow Nova + Confounding Blow (Sacrolash); Conflagration + Blaze (Alythess - move out of fire). Dark/Flame Touched: stand in the matching damage to clear it. Kill close together.",
            }},
            { title = "M'uru", lines = {
                "M'uru - P1: kill the adds (Void Sentinels, Berserkers, Dark Fiends) while tanking M'uru; Negative Energy hits the raid (spread/heal). P2: becomes Entropius - Black Holes (move around them), Darkness, Singularity. HARD enrage - burn.",
            }},
            { title = "Kil'jaeden", lines = {
                "Kil'jaeden - use the Blue Child (Anveena) orbs to strip his shield at the start. Armageddon meteors (move from marks), Shield Orbs (kill), Sinister Reflection (clones), Darkness of a Thousand Souls (raid nuke - heal CDs). Spread for Fire Bloom.",
            }},
            { title = "Assignments", lines = {
                "TANKS: {MT} boss, {OT} {OT2} adds / Meteor Slash soak / 2nd twin. HEALS: {H1} {H2} tank, {H3} {H4} raid (heavy AoE), {H5} flex + dispels.",
                "Kalecgos: SPECTRAL REALM team on Sathrovarr - assign. {DISP} on Wild Magic/Encapsulate/Sleep. {BL} on Brutallus and M'uru enrage windows.",
            }},
        },
    },

}
