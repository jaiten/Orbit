// Generated from shared/onboarding.json by windows/scripts/generate.cjs. Do not edit.
const OrbitOnboardingData = {
  "examples": {
    "lists": [
      {
        "id": "00000000-0000-4000-8000-0000000e0001",
        "name": "Personal",
        "color": "sage"
      }
    ],
    "tasks": [
      {
        "id": "00000000-0000-4000-8000-0000000e0101",
        "title": "Morning walk",
        "time": 480,
        "minutes": 30
      },
      {
        "id": "00000000-0000-4000-8000-0000000e0102",
        "title": "Focus on one thing",
        "time": 600,
        "minutes": 90
      },
      {
        "id": "00000000-0000-4000-8000-0000000e0103",
        "title": "Call someone you miss",
        "list": "00000000-0000-4000-8000-0000000e0001"
      },
      {
        "id": "00000000-0000-4000-8000-0000000e0104",
        "title": "Plan a weekend away",
        "someday": true
      }
    ],
    "habits": [
      {
        "id": "00000000-0000-4000-8000-0000000e0201",
        "title": "Drink water",
        "frequencyRule": "DAILY",
        "target": 6,
        "color": "sage"
      },
      {
        "id": "00000000-0000-4000-8000-0000000e0202",
        "title": "Read a few pages",
        "frequencyRule": "DAILY",
        "target": 1,
        "color": "lavender"
      },
      {
        "id": "00000000-0000-4000-8000-0000000e0203",
        "title": "Move your body",
        "frequencyRule": "WEEKLY",
        "target": 3,
        "color": "clay"
      }
    ]
  },
  "habitSuggestions": [
    {
      "title": "Drink water",
      "frequencyRule": "DAILY",
      "target": 6
    },
    {
      "title": "Read 10 pages",
      "frequencyRule": "DAILY",
      "target": 1
    },
    {
      "title": "Stretch",
      "frequencyRule": "WEEKDAYS",
      "target": 1
    },
    {
      "title": "Walk outside",
      "frequencyRule": "DAILY",
      "target": 1
    },
    {
      "title": "Exercise",
      "frequencyRule": "WEEKLY",
      "target": 3
    },
    {
      "title": "Plan tomorrow",
      "frequencyRule": "DAILY",
      "target": 1,
      "reminderMinutes": 1260
    }
  ]
};
if (typeof module === "object") module.exports = OrbitOnboardingData;
