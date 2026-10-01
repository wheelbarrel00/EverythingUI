"""Every addon that vendors the library, keyed by the id sync.py takes on its command line."""
import os

SIBLING = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ADDONS = {
    'EQOT': {
        'name': 'EQ Objective Tracker',
        'path': os.path.join(SIBLING, 'EQObjectiveTracker'),
    },
    'EQ': {
        'name': 'Everything Quests',
        'path': os.path.join(SIBLING, 'EverythingQuests'),
    },
    'ED': {
        'name': 'Everything Delves',
        'path': os.path.join(SIBLING, 'EverythingDelves'),
    },
    'CDM': {
        'name': 'Cooldown Master',
        'path': os.path.join(SIBLING, 'CooldownMaster'),
    },
    'LootPro': {
        'name': 'Loot Pro',
        'path': os.path.join(SIBLING, 'LootPro'),
    },
}
