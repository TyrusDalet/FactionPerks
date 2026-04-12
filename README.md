Inspired by, and fundamentally REQUIRES: [ErnPerkFramework](https://github.com/ernmw/ErnPerkFramework)

A mod based on the OpenMW Perk Framework that adds several perks to each faction

Special thanks to Blurpandra for making the Perks Framework, and to Arrean in the OpenMW discord for helping me proofread so many mistakes

## Installing

Download the [latest version here]([https://github.com/erinpentecost/ErnPerkFramework/archive/refs/heads/main.zip]).

Extract to your `mods/` folder. In your `openmw.cfg` file, add these lines in the correct spots:

```ini
data="/wherevermymodsare/mods/FactionPerks"
content=FactionPerks.omwscripts
content=FactionPerkSpells.ESP
```


## Major Plans

I want to expand the non-Great House perks a little bit. Thieves Guild and Morag Tong have cool passive abilities at perks 3 and 4, and I want
to bring that level of uniqueness to each other faction.

While the mod innately has compatability with TR_Factions, I eventually want to look at adding perks for Tamriel Rebuilt, Project Cyrodiil, and Skyrim Home of the Nords factions
But I might handle that in a seperate mod.

## Known Issues
The only major issue I've managed to sniff out, that I will be looking at fixing (but it isn't a massive detriment)
is that the extra potion effects in Wit of House Telvanni have their duration handled in real life seconds
Which means that if you rest or wait, the effect isn't removed

Yes, House Telvanni has the most benefits, I want that to be the baseline, but I'm still coming up with ways to bring the
others up to snuff

-----------------------------------------------------------------------------------


# Perks 

All perks in a faction build off of one another
If the perks modify the same attribute or skill, the largest effect applies
Otherwise, the effect persists as you take more perks

## Great Houses ##

Honour the Great House effects:
These are special effects for the Great House, which scale on your faction reputation
They scale up to an expected value based on the reputation required to reach max rank
and beyond that point have reduced scaling.

  Strength of Great House Redoran:
    Damage Threshold, weapon attacks that do less damage than this threshold have their damage negated
    doubled vs Sixth House members and Dreugh.
    Value at Archmaster requirement: 20

  Guile of Great House Hlaalu:
    Increased Disposition with Merchants, and reduces Merchants Mercantile to get you better deals
    Value at Grandmaster requirement: +100 Disposition, -30 Mercantile

  Wit of Great House Telvanni:
    Consumed potions and ingredients will trigger a second time with increased magnitude
    Value at Archmagister requirement: 150% magnitude (For a total of 250% effect)
    Restore Health/Magicka/Fatigue effects are currently applied instantly


## House Redoran

  ### Perk 1: Redoran Pledge
  +5 Strength, +10 Spear, +10 Athletics
  Honour the Great House:
    Strength of Great House Redoran

  # Perk 2: Burden of Duty
  +15 Endurance, +25 Heavy Armor, +25 Block

  # Perk 3: Unbroken Line
  +25 Endurance, +50 Spear, +50 Block

  # Perk 4: Guardian of the House
  +25 Strength, +75 Spear, +75 Heavy Armor


## House Hlaalu

  # Perk 1: Hlaalu Courtesies
  +5 Personality, +10 Speechcraft
  Honour The Great House:
    Guile of Great House Hlaalu

  # Perk 2: Silver Tongue
  +15 Personality, +25 Speechcraft, +25 Illusion

  # Perk 3: Trade Acumen
  +25 Personality, +50 Mercantile

  # Perk 4: Councillor's Ear
  +25 Luck, +75 Speechcraft


## House Telvanni

  # Perk 1: Uninvited Student
  +5 Intelligence, +10 Enchant, +10 Alchemy, +10 Spell Absorption
  Grants Spell:
    Strong Levitate
  Honour the Great House:
    Wit of Great House Telvanni

  # Perk 2: Tower Sorcery
  +15 Intelligence, +25 Enchant, +25 Alchemy, +25 Spell Absorption
  Grants Spells:
    Mark
    Recall

  # Perk 3: Self-Made Power
  +25 Intelligence, +50 Enchant, +50 Alchemy, +50 Spell Absorption
  Fortify Maximum Magicka 0.5x INT
  Restore Magicka 1pt/s

  # Perk 3: Telvanni Lord
  +25 Willpower, +75 Enchant, +75 Alchemy, +75 Spell Absorption
  Fortify Maximum Magicka 1.0x INT
  Restore Magicka 2pts/s


## Imperial Factions ##

## Imperial Legion

  # Perk 1: Legion Recruit
  +5 Endurance, +10 Fortify Fatigue, +10 Medium Armour, +10 Heavy Armour

  # Perk 2: Shield Wall
  +15 Endurance, +25 Fortify Fatigue, +25 Block

  # Perk 3: Forced March
  +25 Endurance, +50 Fortify Fatigue, +50 Athletics
  Grants Power:
    Legion's Prowess
      Fortify Athletics, Strength, Speed, Endurance, Health 50pts for 30s

  # Perk 4: Legate
  +25 Strength, +75 Fortify Fatigue, +75 Heavy Armour
  Restore Health 1pt/s
  Restore Fatigue 1pt/s


## Imperial Cult

  # Perk 1: Lay Worshipper
  +5 Willpower, +10 Resist Disease, +10 Resist Poison, +10 Resist Normal Weapons
  Grants Spell:
    Divine Intervention

  # Perk 2: Charitable Hand
  +15 Willpower, +25 Resist Disease, +25 Resist Poison, +25 Resist Normal Weapons

  # Perk 3: Divine Favour
  +25 Willpower, +50 Resist Disease, +50 Resist Poison, +50 Resist Normal Weapons

  # Perk 4: Blessed of the Nine
  +25 Personality, +75 Resist Disease, +75 Resist Poison, +75 Resist Normal Weapons
  Grants Power:
    Blessing of the Nine
      Fortify all Attributes 50pts for 30s


## Thieves Guild

  # Perk 1: Light Fingers
  +5 Agility, +10 Sneak, +10 Security

  # Perk 2: Shadow Step
  +15 Agility, +25 Sneak, +25 Acrobatics

  # Perk 3: Fence Network
  +20 Agility, +50 Sneak, +50 Mercantile
  25% Chameleon while sneaking

  # Perk 4: Master Thief
  +25 Luck, +75 Security
  50% Chameleon while sneaking


## Fighters Guild

  # Perk 1: Dues Paid
  +5 Strength, +10 Fortify Health

  # Perk 2: Iron Discipline
  +15 Strength, +25 Fortify Health

  # Perk 3: Battle-Tested
  +25 Strength, +50 Fortify Health
  Grants Power:
    Martial Rage
      Fortify Health 50pts for 30s
      Fortify Fatigue 200pts for 30s
      Fortify Attack 100pts for 30s

  # Perk 4: Champion of the Guild
  +25 Endurance, +75 Fortify Health
  Restore Health 1pt/s
  Restore Fatigue 1pt/s


## Mages Guild

  # Perk 1: Guild Initiate
  +5 Intelligence, +10 Fortify Magicka

  # Perk 2: Scholastic Rigour
  +15 Intelligence, +25 Fortify Magicka

  # Perk 3: Arcane Reservoir
  +25 Intelligence, +50 Fortify Magicka
  Fortify Maximum Magicka 0.5x INT

  # Perk 4: Archmagister's Peer
  +25 Willpower, +75 Fortify Magicka
  Fortify Maximum Magicka 1.0x INT


## Morrowind Factions ##

## Tribunal Temple

  # Perk 1: Ordinate Aspirant
  +5 Intelligence, +10 Reflect, +10 Resist Paralysis, +10 Resist Blight Disease
  Grants Spell:
    Almsivi Intervention

  # Perk 2: Pilgrim Soul
  +15 Intelligence, +25 Reflect, +25 Resist Paralysis, +25 Resist Blight Disease
  Grants Power:
    Touch of ALMSIVI
      Cure Common Disease, Cure Blight Disease, Cure Poison on Touch

  # Perk 3: Voice of Reclaimation
  +25 Intelligence, +50 Reflect, +50 Resist Paralysis, +50 Resist Blight Disease

  # Perk 4: Hand of ALMSIVI
  +25 Personality, +75 Reflect, +75 Resist Paralysis, +75 Resist Blight Disease
  Grants Power:
    Call Honoured Ancestors
      Summon 2x Greater Bonewalker 60s
      Summon 2x Bonelord 60s


## Morag Tong

  # Perk 1: Writ Bearer
  +5 Speed, +10 Short Blade, +10 Speechcraft

  # Perk 2: Blade Discipline
  +15 Speed, +25 Short Blade, +25 Light Armour
  Grants Spell:
    Mephala's Touch
      Frenzy Humanoid 50pts for 30s

  # Perk 3: Calm Before
  +25 Speed, +50 Sneak, +50 Short Blade

  # Perk 4: Honoured Executioner
  +25 Strength, +75 Short Blade
  Weapon attacks whilst sneaking apply a 25pt for 5s Absorb Health effect
  Grants Power:
    Mephala's Shroud
      Invisibility for 60s
