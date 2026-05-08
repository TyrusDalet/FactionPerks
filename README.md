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


-----------------------------------------------------------------------------------


# Perks 

All perks in a faction build off of one another

If the perks modify the same attribute or skill, the largest effect applies

Otherwise, the effect persists as you take more perks

# Great Houses #

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
  
    Constant Effect and Cast On use Enchantments will trigger a second time with increased magnitude
    Value at Archmagister requirement: 150% magnitude (For a total of 250% effect)
    Restore Health/Magicka/Fatigue effects are currently applied instantly
    Constant Effect enchantments are hard-capped at +200% power


## House Redoran


### Perk 1: Redoran Pledge 
+3 Str/End, +10 Health, +5 Medium Armour / Athletics

Honour the Great House:

    Strength of Great House Redoran

### Perk 2: Burden of Duty 
+5 Str/End, +20 Health, +10 Medium Armour / Athletics

### Perk 3: Unbroken Line 
+10 Str/End, +35 Health, +18 Medium Armour / Athletics

### Perk 4: Guardian of the House 
+15 Str/End, +50 Health, +25 Medium Armour / Athletics



## House Hlaalu


### Perk 1: Hlaalu Courtesies 
+3 Per/Agi, +5 Mercantile / Speechcraft

Honour The Great House:

    Guile of Great House Hlaalu

### Perk 2: Silver Tongue 
+5 Per/Agi, +10 Mercantile / Speechcraft

### Perk 3: Trade Acumen 
+10 Per/Agi, +18 Mercantile / Speechcraft

### Perk 4: Councillor’s Ear 
+15 Per/Agi, +25 Mercantile / Speechcraft



## House Telvanni

### Perk 1: Uninvited Student 
+3 Int/Wil, +5 Enchant / Conjuration

Grants Spell:

    Bound Helm
    Bound Cuirass


Honour the Great House:

    Wit of Great House Telvanni

### Perk 2: Tower Sorcery 
+5 Int/Wil, +10 Enchant / Conjuration

Grants Spells:

    Tranasa's Spelltrap 

### Perk 3: Self-Made Power 
+10 Int/Wil, +18 Enchant / Conjuration

Restore Magicka 1pt/s

### Perk 4: Telvanni Lord 
+15 Int/Wil, +25 Enchant / Conjuration

Restore Magicka 2pts/s



# Imperial Factions

## Imperial Legion


### Perk 1: Legion Recruit 
+3 End/Str, +5 Heavy Armour / Block, +10 Fatigue

### Perk 2: Shield Wall 
+5 End/Str, +10 Heavy Armour / Block, +20 Fatigue

Legionary's Resolve:

    Blocking does damage to your attacker
    Damage is equal to 1/4 your Block Skill
    Blocking restores 30% of fatigue used

### Perk 3: Forced March
+10 End/Str, +18 Heavy Armour / Block, +35 Fatigue

Blocking Fatigue Restoration: 50%

Grants Power:

    Legion's Prowess

      Fortify Athletics, Strength, Speed, Endurance, Health 50pts for 30s

### Perk 4: Legate 
+15 End/Str, +25 Heavy Armour / Blockk, +50 Fatigue

Blocking Fatigue Restoration: 75%

Restore Health 1pt/s
Restore Fatigue 1pt/s


## Imperial Cult

### Perk 1: Lay Worshipper 
+3 Wil/Per, +5 Speechcraft / Restoration

Grants Spell:

    Divine Intervention

### Perk 2: Charitable Hand 
+5 Wil/Per, +10 Speechcraft / Restoration

### Perk 3: Divine Favour 
+10 Wil/Per, +18 Speechcraft / Restoration

Divine Smite:

    Striking Undead, Vampires, or Daedra deals extra damage
    Damage = 10x Imperial Cult Rank
    10s Cooldown per target

### Perk 4: Blessed of the Nine 
+15 Wil/Per, +25 Speechcraft / Restoration

Smite Cooldown : 5s

Grants Power:

    Blessing of the Nine

      Fortify all Attributes 50pts for 30s


## Thieves Guild

### Perk 1: Light Fingers 
+3 Agi/Spd, +5 Sneak / Security

### Perk 2: Shadow Step 
+5 Agi/Spd, +10 Sneak / Security

### Perk 3: Fence Network 
+10 Agi/Spd, +18 Sneak / Security

25% Chameleon while sneaking

### Perk 4: Master Thief 
+15 Agi/Spd, +25 Sneak / Security

50% Chameleon while sneaking



## Fighters Guild

### Perk 1: Dues Paid 
+3 Str/End, +10 Health, +5 Long Blade / Blunt / Axe

### Perk 2: Iron Discipline 
+5 Str/End, +20 Health, +10 Long Blade / Blunt / Axe

Counterattack with held weapon on enemy miss - 10s cooldown

### Perk 3: Battle-Tested 
+10 Str/End, +35 Health, +18 Long Blade / Blunt / Axe

Counterattack cooldown: 6s

Grants Power:

    Martial Rage

      Fortify Health 50pts for 30s
      Fortify Fatigue 200pts for 30s
      Fortify Attack 100pts for 30s

### Perk 4: Champion of the Guild 
+15 Str/End, +50 Health, +25 Long Blade / Blunt / Axe

Counterattack cooldown: 1.5s


## Mages Guild

### Perk 1: Guild Initiate 
+3 Int/End, +10 Magicka, +5 Destruction / Alteration

### Perk 2: Scholastic Rigour 
+5 Int/End, +20 Magicka, +10 Destruction / Alteration

Magical Cartography:

    Visiting places of power grants 1% Resist Magicka and 2pts Detect Enchantment
    Every 10 places visted grants 5% magicka refund on spells (max 25%)

### Perk 3: Arcane Reservoir 
+10 Int/End, +35 Magicka, +18 Destruction / Alteration

Fortify Maximum Magicka 0.5x INT

### Perk 4: Archmagister’s Peer 
+15 Int/End, +50 Magicka, +25 Destruction / Alteration

Fortify Maximum Magicka 1.0x INT



# Morrowind Factions



## Tribunal Temple


### Perk 1: Ordinate Aspirant 
+3 Int/Wil, +5 Restoration / Mysticism

Grants Spell:

    Almsivi Intervention

### Perk 2: Pilgrim Soul 
+5 Int/Wil, +10 Restoration / Mysticism

Grants Power:

    Touch of ALMSIVI

      Cure Common Disease, Cure Blight Disease, Cure Poison on Touch

### Perk 3: Voice of Reclaimation 
+10 Int/Wil, +18 Restoration / Mysticism

Non-summoned Bonewalkers, Bonelords, and Ancestor Ghosts are no longer aggressive

### Perk 4: Hand of ALMSIVI 
+15 Int/Wil, +25 Restoration / Mysticism

Grants Power:

    Call Honoured Ancestors

      Summon 2x Greater Bonewalker 60s
      Summon 2x Bonelord 60s



## Morag Tong


### Perk 1: Writ Bearer 
+3 Spd/Agi, +5 Sneak / Acrobatics

### Perk 2: Blade Discipline 
+5 Spd/Agi, +10 Sneak / Acrobatics

Grants Spell:

    Mephala's Touch

      Frenzy Humanoid 50pts for 30s

### Perk 3: Calm Before 
+10 Spd/Agi, +18 Sneak / Acrobatics

### Perk 4: Honoured Executioner 
+15 Spd/Agi, +25 Sneak / Acrobatics

Weapon attacks whilst sneaking apply a 25pt for 5s Absorb Health effect

  
  Grants Power:
  
    Mephala's Shroud
    
      Invisibility for 60s
