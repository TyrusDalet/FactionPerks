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
+3 Str/End, +10 Health, +5 Blade/Blunt/Axe

Honour the Great House:

    Strength of Great House Redoran

### Perk 2: Burden of Duty 
+5 Str/End, +20 Health, +10 Blade/Blunt/Axe

### Perk 3: Unbroken Line 
+10 Str/End, +35 Health, +18 Blade/Blunt/Axe

### Perk 4: Guardian of the House 
+15 Str/End, +50 Health, +25 Blade/Blunt/Axe

## House Hlaalu

### Perk 1: Hlaalu Courtesies +3 Per/Agi, +5 Merc/Speech

Honour The Great House:

    Guile of Great House Hlaalu

### Perk 2: Silver Tongue +5 Per/Agi, +10 Merc/Speech

### Perk 3: Trade Acumen +10 Per/Agi, +18 Merc/Speech

### Perk 4: Councillor’s Ear +15 Per/Agi, +25 Merc/Speech

##House Telvanni

### Perk 1: Uninvited Student +3 Int/Wil, +5 Enchant/Conj

Grants Spell:

    Bound Helm
    Bound Cuirass


Honour the Great House:

    Wit of Great House Telvanni

### Perk 2: Tower Sorcery +5 Int/Wil, +10 Enchant/Conj

Grants Spells:

    Tranasa's Spelltrap 

### Perk 3: Self-Made Power +10 Int/Wil, +18 Enchant/Conj

Fortify Maximum Magicka 0.5x INT

Restore Magicka 1pt/s

### Perk 4: Telvanni Lord +15 Int/Wil, +25 Enchant/Conj

Fortify Maximum Magicka 1.0x INT

Restore Magicka 2pts/s

#Imperial Factions

##Imperial Legion

### Perk 1: Legion Recruit +3 End/Str, +5 IvyArmour/Block, +10 Fatigue

### Perk 2: Shield Wall +5 End/Str, +10 IvyArmour/Block, +20 Fatigue

### Perk 3: Forced March +10 End/Str, +18 IvyArmour/Block, +35 Fatigue

Grants Power:

    Legion's Prowess

      Fortify Athletics, Strength, Speed, Endurance, Health 50pts for 30s

### Perk 4: Legate +15 End/Str, +25 IvyArmour/Block, +50 Fatigue

Restore Health 1pt/s

Restore Fatigue 1pt/s

##Imperial Cult

### Perk 1: Lay Worshipper +3 Wil/Per, +5 Speech/Resto

Grants Spell:

    Divine Intervention

### Perk 2: Charitable Hand +5 Wil/Per, +10 Speech/Resto

### Perk 3: Divine Favour +10 Wil/Per, +18 Speech/Resto

### Perk 4: Blessed of the Nine +15 Wil/Per, +25 Speech/Resto

Grants Power:

    Blessing of the Nine

      Fortify all Attributes 50pts for 30s

##Thieves Guild

### Perk 1: Light Fingers +3 Agi/Spd, +5 Sneak/Security

### Perk 2: Shadow Step +5 Agi/Spd, +10 Sneak/Security

### Perk 3: Fence Network +10 Agi/Spd, +18 Sneak/Security

25% Chameleon while sneaking

### Perk 4: Master Thief +15 Agi/Spd, +25 Sneak/Security

50% Chameleon while sneaking

##Fighters Guild

### Perk 1: Dues Paid +3 Str/End, +10 Health, +5 Blade/Blunt/Axe

### Perk 2: Iron Discipline +5 Str/End, +20 Health, +10 Blade/Blunt/Axe

### Perk 3: Battle-Tested +10 Str/End, +35 Health, +18 Blade/Blunt/Axe

Grants Power:

    Martial Rage

      Fortify Health 50pts for 30s
      Fortify Fatigue 200pts for 30s
      Fortify Attack 100pts for 30s

### Perk 4: Champion of the Guild +15 Str/End, +50 Health, +25
Blade/Blunt/Axe

##Mages Guild

### Perk 1: Guild Initiate +3 Int/End, +10 Magicka, +5 Dest/Alt

### Perk 2: Scholastic Rigour +5 Int/End, +20 Magicka, +10 Dest/Alt

### Perk 3: Arcane Reservoir +10 Int/End, +35 Magicka, +18 Dest/Alt

Fortify Maximum Magicka 0.5x INT

### Perk 4: Archmagister’s Peer +15 Int/End, +50 Magicka, +25 Dest/Alt

Fortify Maximum Magicka 1.0x INT

#Morrowind Factions

##Tribunal Temple

### Perk 1: Ordinate Aspirant +3 Int/Wil, +5 Resto/Myst

Grants Spell:

    Almsivi Intervention

### Perk 2: Pilgrim Soul +5 Int/Wil, +10 Resto/Myst

Grants Power:

    Touch of ALMSIVI

      Cure Common Disease, Cure Blight Disease, Cure Poison on Touch

### Perk 3: Voice of Reclaimation +10 Int/Wil, +18 Resto/Myst

### Perk 4: Hand of ALMSIVI +15 Int/Wil, +25 Resto/Myst

Grants Power:

    Call Honoured Ancestors

      Summon 2x Greater Bonewalker 60s
      Summon 2x Bonelord 60s

##Morag Tong

### Perk 1: Writ Bearer +3 Spd/Agi, +5 Sneak/Acrobatics

### Perk 2: Blade Discipline +5 Spd/Agi, +10 Sneak/Acrobatics

Grants Spell:

    Mephala's Touch

      Frenzy Humanoid 50pts for 30s

### Perk 3: Calm Before +10 Spd/Agi, +18 Sneak/Acrobatics

### Perk 4: Honoured Executioner +15 Spd/Agi, +25 Sneak/Acrobatics

Weapon attacks whilst sneaking apply a 25pt for 5s Absorb Health effect

  
  Grants Power:
  
    Mephala's Shroud
    
      Invisibility for 60s
