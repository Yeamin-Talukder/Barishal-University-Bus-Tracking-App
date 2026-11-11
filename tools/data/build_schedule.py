"""Builds assets/data/schedule.json, the official bus schedule.

Source: screenshots of the university's "Bus Schedule" screen, supplied by
the project owner on 2026-11-10. Everything in SCHEDULE below is copied from
those screenshots as written, in Bangla. Nothing is added: routes whose stop
list was blank on the screen have no stops here.

The English text is a transliteration added by this script so the app can
show both. It is not part of the official schedule.

Run from the project root:  python tools/data/build_schedule.py
"""

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "data" / "schedule.json"

# Bangla -> English, longest names first when applied.
ENGLISH = {
    # Departure places and stops
    "বিশ্ববিদ্যালয়": "University",
    "বরিশাল ক্লাব": "Barishal Club",
    "নতুন বাজার (টেম্পু স্ট্যান্ড)": "Notun Bazar (Tempo Stand)",
    "নতুন বাজার (টেম্পুস্ট্যান্ড)": "Notun Bazar (Tempo Stand)",
    "নথুল্লাবাদ ব্রীজের ঢাল": "Nathullabad Bridge Slope",
    "নথুল্লাবাদ": "Nathullabad",
    "চৌমাথা মোড়": "Chowmatha Mor",
    "ট্রাস্ট ভবন": "Trust Bhaban",
    "বাংলাবাজার মোড়": "Bangla Bazar Mor",
    "নুরিয়া স্কুল": "Nuria School",
    "আমতলার মোড়": "Amtala Mor",
    "রুপাতলী হাউজিং": "Rupatoli Housing",
    "কাঠালতলা": "Kathaltola",
    "কাঁঠালতলা": "Kathaltola",
    "টোলঘর": "Toll Ghar",
    "মুন্সি গ্যারেজ": "Munshi Garage",
    "অপসোনিন মোড়": "Opsonin Mor",
    "বটতলার মোড়": "Bottola Mor",
    "করিমকুটির": "Karim Kutir",
    "কলেজ এভিনিউ": "College Avenue",
    "টিটিসি মূল গেট": "TTC Main Gate",
    "থানা কাউন্সিলের মূল গেট": "Thana Council Main Gate",
    # Vehicles
    "বিআরটিসি": "BRTC",
    "মাইক্রো": "Micro",
    "বৈকালি": "Boikali",
    "বৈকালী": "Boikali",
    "চিত্রা": "Chitra",
    "কীর্তনখোলা": "Kirtankhola",
    "জয়ন্তী": "Jayanti",
    "লতা": "Lota",
    "পায়রা": "Payra",
    "সুগন্ধা": "Sugandha",
    "সন্ধ্যা": "Sandhya",
    "আগুনমুখা": "Agunmukha",
    "আন্ধারমানিক": "Andharmanik",
    "নয়াভাঙ্গানী": "Noyabhangani",
    "ইলিশা": "Ilisha",
    # Words
    "২টি বাস": "2 buses",
    " ও ": " and ",
}

DIGITS = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")

ANY_OF_SIX = "লতা/কীর্তনখোলা/পায়রা/চিত্রা/বৈকালি/জয়ন্তী"


def english(text: str) -> str:
    result = text
    for bangla in sorted(ENGLISH, key=len, reverse=True):
        result = result.replace(bangla, ENGLISH[bangla])
    result = result.translate(DIGITS)
    leftover = re.findall(r"[ঀ-৿]+", result)
    if leftover:
        raise SystemExit(f"No English for {leftover} in {text!r}")
    return result


def time24(text: str) -> str:
    match = re.fullmatch(r"(\d{1,2}):(\d{2}) (AM|PM)", text)
    if not match:
        raise SystemExit(f"Bad time {text!r}")
    hour, minute, half = int(match[1]), int(match[2]), match[3]
    if half == "AM" and hour == 12:
        hour = 0
    elif half == "PM" and hour != 12:
        hour += 12
    return f"{hour:02d}:{minute:02d}"


# (group, route number, stops as written or None, [(departure place, [(time, vehicles)])])
# Departure places are in the order shown on the screen.
SCHEDULE = [
    (
        "student",
        "01",
        "বরিশাল ক্লাব - বাংলাবাজার মোড় - নুরিয়া স্কুল - আমতলার মোড় - "
        "রুপাতলী হাউজিং - কাঠালতলা - টোলঘর - বিশ্ববিদ্যালয়",
        [
            (
                "বিশ্ববিদ্যালয়",
                [
                    ("8:30 AM", "বৈকালি, বিআরটিসি-০৬"),
                    ("9:30 AM", "চিত্রা, বিআরটিসি-০৫"),
                    ("10:30 AM", "বিআরটিসি-০৪"),
                    ("11:15 AM", "বিআরটিসি-০৫"),
                    ("12:10 PM", "কীর্তনখোলা, বিআরটিসি-০৬"),
                    ("1:15 PM", "জয়ন্তী, বিআরটিসি-০৪"),
                    ("2:15 PM", "বৈকালি, বিআরটিসি-০৬"),
                    ("3:10 PM", "বিআরটিসি-০৪,০৫"),
                    ("4:10 PM", "চিত্রা, বিআরটিসি-০৪,০৬"),
                    ("5:10 PM", "চিত্রা ও বৈকালি"),
                    ("6:45 PM", ANY_OF_SIX),
                    ("9:00 PM", ANY_OF_SIX),
                ],
            ),
            (
                "বরিশাল ক্লাব",
                [
                    ("7:30 AM", "বিআরটিসি-০৬"),
                    ("8:30 AM", "বিআরটিসি-০৪,০৫"),
                    ("9:15 AM", "বৈকালি, বিআরটিসি-০৬"),
                    ("10:15 AM", "চিত্রা, বিআরটিসি-০৫"),
                    ("11:15 AM", "বিআরটিসি-০৪"),
                    ("12:00 PM", "বিআরটিসি-০৫"),
                    ("1:00 PM", "কীর্তনখোলা, বিআরটিসি-০৬"),
                    ("2:00 PM", "জয়ন্তী, বিআরটিসি-০৪"),
                    ("3:00 PM", "বৈকালী, বিআরটিসি-০৬"),
                    ("3:40 PM", "বিআরটিসি-০৪,০৫"),
                    ("4:40 PM", "চিত্রা"),
                    ("8:30 PM", "২টি বাস (" + ANY_OF_SIX + ")"),
                    ("9:30 PM", ANY_OF_SIX),
                ],
            ),
        ],
    ),
    (
        "student",
        "02",
        # The published schedule lists only the first five places and the
        # University for this route. The owner said (11 November 2026) that
        # from Karim Kutir the bus goes to Chowmatha and then runs and stops
        # as routes 01 and 03 do, so those places are added here, with the
        # names route 03's list gives them.
        "নতুন বাজার (টেম্পু স্ট্যান্ড) - মুন্সি গ্যারেজ - অপসোনিন মোড় - "
        "বটতলার মোড় - করিমকুটির - চৌমাথা মোড় - থানা কাউন্সিলের মূল গেট - "
        "আমতলার মোড় - রুপাতলী হাউজিং - কাঁঠালতলা - টোলঘর - বিশ্ববিদ্যালয়",
        [
            (
                "বিশ্ববিদ্যালয়",
                [
                    ("7:45 AM", "সুগন্ধা"),
                    ("8:30 AM", "সন্ধ্যা"),
                    ("9:30 AM", "আগুনমুখা"),
                    ("10:30 AM", "সুগন্ধা"),
                    ("11:15 AM", "সন্ধ্যা"),
                    ("12:10 PM", "আগুনমুখা"),
                    ("1:15 PM", "সুগন্ধা"),
                    ("2:15 PM", "আন্ধারমানিক"),
                    ("3:10 PM", "সন্ধ্যা"),
                    ("4:10 PM", "সন্ধ্যা, সুগন্ধা"),
                ],
            ),
            (
                "নতুন বাজার (টেম্পুস্ট্যান্ড)",
                [
                    ("7:30 AM", "আন্ধারমানিক"),
                    ("8:30 AM", "সুগন্ধা"),
                    ("9:15 AM", "সন্ধ্যা"),
                    ("10:15 AM", "আগুনমুখা, আন্ধারমানিক"),
                    ("11:15 AM", "সুগন্ধা"),
                    ("12:00 PM", "সন্ধ্যা"),
                    ("12:45 PM", "আগুনমুখা"),
                    ("1:50 PM", "সুগন্ধা"),
                    ("2:45 PM", "আন্ধারমানিক"),
                    ("3:40 PM", "সন্ধ্যা"),
                    ("4:40 PM", "সন্ধ্যা, সুগন্ধা"),
                ],
            ),
        ],
    ),
    (
        "student",
        "03",
        "নথুল্লাবাদ ব্রীজের ঢাল - কলেজ এভিনিউ - টিটিসি মূল গেট - চৌমাথা মোড় - "
        "থানা কাউন্সিলের মূল গেট - আমতলার মোড় - রুপাতলী হাউজিং - কাঁঠালতলা - "
        "টোলঘর - বিশ্ববিদ্যালয়",
        [
            (
                "নথুল্লাবাদ ব্রীজের ঢাল",
                [
                    ("7:30 AM", "বিআরটিসি-০৭"),
                    ("8:30 AM", "বিআরটিসি-০৮,১১"),
                    ("9:15 AM", "বিআরটিসি-০৯,১০"),
                    ("10:15 AM", "বিআরটিসি-১২,১৩,১৪"),
                    ("11:15 AM", "বিআরটিসি-০৭,১১"),
                    ("12:00 PM", "বিআরটিসি-০৮,০৯"),
                    ("12:30 PM", "বিআরটিসি-১০,১২"),
                    ("1:00 PM", "বিআরটিসি-০৭,১৩"),
                    ("2:00 PM", "বিআরটিসি-০৮"),
                    ("3:00 PM", "বিআরটিসি-১৪"),
                    ("3:30 PM", "বিআরটিসি-১২"),
                    ("4:30 PM", "বিআরটিসি-০৯"),
                    ("8:30 PM", "বিআরটিসি-০৮,১৩"),
                    ("9:30 PM", "বিআরটিসি-০৮,১৩"),
                ],
            ),
            (
                "বিশ্ববিদ্যালয়",
                [
                    ("8:30 AM", "বিআরটিসি-০৭"),
                    ("9:30 AM", "বিআরটিসি-০৮,১১"),
                    ("10:00 AM", "বিআরটিসি-০৯,১০"),
                    ("11:15 AM", "বিআরটিসি-১২,১৩"),
                    ("12:10 PM", "বিআরটিসি-০৭,১১"),
                    ("1:15 PM", "বিআরটিসি-০৮,০৯"),
                    ("2:15 PM", "বিআরটিসি-১২,১৪"),
                    ("3:10 PM", "বিআরটিসি-০৭,১৩"),
                    ("4:10 PM", "বিআরটিসি-০৮,১০,১৪"),
                    ("5:10 PM", "বিআরটিসি-০৯,১২"),
                    ("6:45 PM", ANY_OF_SIX),
                    ("9:00 PM", "বিআরটিসি-০৮,১৩"),
                    ("10:00 PM", "বিআরটিসি-০৮,১৩"),
                ],
            ),
        ],
    ),
    (
        "teacher",
        "04",
        None,
        [
            ("বিশ্ববিদ্যালয়", [("2:00 PM", "মাইক্রো-০৪"), ("4:05 PM", "নয়াভাঙ্গানী")]),
            (
                "চৌমাথা মোড়",
                [
                    ("8:30 AM", "নয়াভাঙ্গানী"),
                    ("9:50 AM", "নয়াভাঙ্গানী"),
                    ("12:00 PM", "মাইক্রো-০২"),
                ],
            ),
        ],
    ),
    (
        "teacher",
        "05",
        None,
        [
            ("বিশ্ববিদ্যালয়", [("7:00 PM", "ইলিশা")]),
            ("চৌমাথা মোড়", [("7:30 AM", "মাইক্রো-০৪")]),
        ],
    ),
    (
        "teacher",
        "06",
        None,
        [
            (
                "চৌমাথা মোড়",
                [("8:30 AM", "ইলিশা"), ("10:00 AM", "লতা"), ("12:00 PM", "ইলিশা")],
            ),
            ("বিশ্ববিদ্যালয়", [("2:00 PM", "নয়াভাঙ্গানী"), ("4:05 PM", "লতা")]),
        ],
    ),
    (
        "teacher",
        "07",
        None,
        [
            ("বিশ্ববিদ্যালয়", [("2:00 PM", "মাইক্রো-০৩"), ("4:05 PM", "মাইক্রো-০৩")]),
            (
                "ট্রাস্ট ভবন",
                [
                    ("9:00 AM", "মাইক্রো-০৩"),
                    ("10:30 AM", "মাইক্রো-০৩"),
                    ("12:30 PM", "মাইক্রো-০৩"),
                ],
            ),
        ],
    ),
    (
        "staff",
        "04",
        None,
        [
            ("চৌমাথা মোড়", [("8:30 AM", "আগুনমুখা")]),
            ("বিশ্ববিদ্যালয়", [("4:05 PM", "আগুনমুখা")]),
        ],
    ),
    (
        "staff",
        "05",
        None,
        [
            ("চৌমাথা মোড়", [("8:25 AM", "মাইক্রো-০৫"), ("8:25 AM", "আন্ধারমানিক")]),
            ("বিশ্ববিদ্যালয়", [("4:05 PM", "মাইক্রো-০৫"), ("4:10 PM", "সুগন্ধা")]),
        ],
    ),
    (
        "staff",
        "06",
        None,
        [
            ("চৌমাথা মোড়", [("8:30 AM", "কীর্তনখোলা")]),
            ("বিশ্ববিদ্যালয়", [("4:05 PM", "কীর্তনখোলা")]),
        ],
    ),
    (
        "staff",
        "08",
        None,
        [
            ("বিশ্ববিদ্যালয়", [("4:10 PM", "বৈকালি"), ("4:10 PM", "জয়ন্তী")]),
            ("নথুল্লাবাদ", [("8:20 AM", "জয়ন্তী")]),
        ],
    ),
]

GROUPS = [
    {"id": "student", "name": "Student"},
    {"id": "teacher", "name": "Teacher"},
    {"id": "staff", "name": "Staff"},
]


def text_pair(bangla: str) -> dict:
    return {"bn": bangla, "en": english(bangla)}


def build() -> dict:
    timetables = []
    for group, route, stops, departures in SCHEDULE:
        stop_list = (
            [text_pair(name.strip()) for name in stops.split(" - ")] if stops else []
        )
        timetables.append(
            {
                "group": group,
                "route": route,
                "stops": stop_list,
                "departures": [
                    {
                        "from": text_pair(place),
                        "trips": [
                            {"time": time24(time), "vehicles": text_pair(vehicles)}
                            for time, vehicles in trips
                        ],
                    }
                    for place, trips in departures
                ],
            }
        )
    return {
        "version": 1,
        "source": "University of Barishal bus schedule, from screenshots of the "
        "university's Bus Schedule screen supplied by the project owner.",
        "recordedOn": "2026-11-10",
        "notes": [
            "The Bangla text is copied as written. The English text is a "
            "transliteration and is not part of the official schedule.",
            "The schedule does not say on which days it applies.",
            "Routes 04 to 08 had no list of stops on the screen.",
        ],
        "groups": GROUPS,
        "timetables": timetables,
    }


def main() -> None:
    data = build()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    trips = sum(
        len(d["trips"]) for t in data["timetables"] for d in t["departures"]
    )
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {len(data['timetables'])} timetables, {trips} departures")
    for t in data["timetables"]:
        counts = ", ".join(
            f"{d['from']['en']} {len(d['trips'])}" for d in t["departures"]
        )
        print(f"  {t['group']:8} route {t['route']}: {len(t['stops'])} stops; {counts}")


if __name__ == "__main__":
    main()
