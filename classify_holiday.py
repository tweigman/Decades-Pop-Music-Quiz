#!/usr/bin/env python3
"""Fill the Difficulty column for categories/holiday.csv.

    python3 classify_holiday.py [--apply]

Chart peak is a bad difficulty proxy here: 129 of 201 holiday songs never
made the Hot 100, so they all default to 'difficult' -- including Silent
Night. These are hand assignments.

The rule, given that naming *either* the song or the artist scores:

  easy       the song is a standard nearly anyone can name, in a recording
             people have actually heard (Bing Crosby, Nat King Cole, the
             Peanuts soundtrack, Brenda Lee)
  harder     a famous song in an unfamiliar arrangement (the Spotify Singles
             covers), a big-artist modern holiday single, a UK standard that
             never crossed over, or a well-known instrumental
  difficult  recent album cuts and one-off singles with no cultural foothold

Entries are keyed by row number but carry a title prefix that is verified
before anything is written, so a renumbered CSV fails loudly instead of
silently mislabelling songs.
"""

import csv
import sys

CSV_PATH = "categories/holiday.csv"

# (row, level, title must start with) -- songs with no Hot 100 entry.
UNCHARTED = [
    (3, "difficult", "santa doesn"), (10, "harder", "Winter Wonderland"),
    (16, "harder", "O Holy Night"), (20, "harder", "A Nonsense Christmas"),
    (21, "difficult", "Coming Home"), (22, "harder", "My Only Wish"),
    (23, "difficult", "Christmas Lights"), (25, "difficult", "Merry Christmas, Please"),
    (26, "harder", "Blue Christmas"), (29, "difficult", "Just For Christmas"),
    (30, "difficult", "You Deserve It All"), (31, "harder", "Christmas (Baby"),
    (32, "difficult", "old fashioned"), (35, "difficult", "1 Wish"),
    (36, "harder", "River"), (37, "difficult", "canal street"),
    (38, "difficult", "Officially Christmas"), (39, "difficult", "secret santa"),
    (40, "difficult", "promise to me"), (41, "harder", "Have Yourself"),
    (42, "harder", "This Christmas"), (43, "difficult", "Not Just On Christmas"),
    (44, "difficult", "Gifts For Me"), (45, "harder", "Driving Home"),
    (46, "harder", "You’re A Mean One"), (47, "difficult", "Love to Keep Me Warm"),
    (48, "difficult", "Under the Tree"), (49, "difficult", "I Wanna Be Your"),
    (50, "difficult", "December 25th"), (52, "difficult", "I'll Be Home"),
    (53, "harder", "One More Sleep"), (54, "harder", "Merry Christmas, Happy"),
    (55, "difficult", "Merry Christmas, i miss"), (56, "difficult", "Scotland In The Snow"),
    (58, "difficult", "Christmas the Whole Year"), (59, "harder", "Santa Claus Is Coming"),
    (60, "difficult", "Dear Santa"), (61, "difficult", "Home to Me"),
    (62, "difficult", "Christmas Without You"), (63, "harder", "Sleigh Ride"),
    (64, "difficult", "Winter Song"), (65, "difficult", "You For Christmas"),
    (66, "difficult", "I Don't Need It"), (67, "difficult", "Hot in December"),
    (69, "difficult", "Christmas Magic"), (70, "difficult", "Make It To Christmas"),
    (71, "easy", "Step Into Christmas"), (72, "difficult", "Please Santa Please"),
    (73, "harder", "Jingle Bell Rock"), (75, "difficult", "Back Home For Christmas"),
    (76, "harder", "Santa's Coming for Us"), (78, "harder", "I'll Be Home For Christmas"),
    (80, "difficult", "Kissing In the Cold"), (81, "harder", "Christmas Wrapping"),
    (82, "easy", "Silent Night"), (83, "harder", "What Christmas Means"),
    (84, "difficult", "Hot Cocoa"), (85, "difficult", "Don't Give Your Heart"),
    (86, "difficult", "Glittery"), (87, "harder", "8 Days of Christmas"),
    (88, "harder", "Man With The Bag"), (90, "harder", "merry christmas darling"),
    (96, "easy", "Carol of the Bells"), (97, "harder", "A Nonsense Christmas"),
    (101, "easy", "Santa Claus Is Comin"), (102, "easy", "Have Yourself"),
    (104, "easy", "Step Into Christmas"), (106, "harder", "O Come All Ye Faithful"),
    (109, "easy", "Christmas Time Is Here"), (110, "harder", "Merry Christmas Everyone"),
    (112, "harder", "Fairytale of New York"), (114, "harder", "What Christmas Means"),
    (115, "harder", "Where Are You Christmas"), (116, "easy", "Deck The Hall"),
    (118, "easy", "Ave Maria"), (120, "easy", "Let It Snow"),
    (122, "easy", "Rudolph"), (123, "harder", "Thank God It's Christmas"),
    (124, "harder", "Hard Candy Christmas"), (127, "harder", "Christmas Eve / Sarajevo"),
    (129, "harder", "Merry Christmas, Happy"), (131, "easy", "Do You Hear What I Hear"),
    (136, "easy", "Winter Wonderland"), (137, "easy", "Frosty"),
    (138, "harder", "Driving Home"), (139, "difficult", "We Wish You The Merriest"),
    (141, "harder", "Christmas (Baby"), (142, "harder", "Someday At Christmas"),
    (143, "easy", "Sleigh Ride"), (144, "harder", "I Wish It Could Be"),
    (145, "harder", "Christmas In Hollis"), (146, "easy", "The First No"),
    (147, "easy", "Here Comes Santa Claus"), (149, "easy", "Joy To The World"),
    (150, "difficult", "Lonely This Christmas"), (151, "easy", "Jingle Bell Rock"),
    (155, "harder", "I Want a Hippopotamus"), (158, "easy", "Santa Claus Is Coming"),
    (160, "easy", "Have Yourself"), (161, "easy", "Christmas Time Is Here"),
    (165, "easy", "God Rest Ye Merry"), (166, "difficult", "Cool Yule"),
    (168, "difficult", "A Marshmallow World"), (169, "harder", "(Everybody's Waitin'"),
    (170, "easy", "Frosty"), (171, "harder", "Caroling, Caroling"),
    (173, "harder", "Merry Christmas Darling"), (174, "easy", "Silver Bells"),
    (177, "easy", "O Tannenbaum"), (178, "harder", "I've Got My Love"),
    (179, "easy", "O Come All Ye Faithful"), (180, "easy", "My Favourite Things"),
    (181, "easy", "The First No"), (182, "easy", "The Little Drummer Boy"),
    (183, "harder", "Mary's Boy Child"), (184, "easy", "O Little Town"),
    (187, "harder", "Mistletoe And Holly"), (189, "harder", "What Are You Doing New Year"),
    (190, "easy", "Silent Night"), (192, "easy", "Here We Come a-Caroling"),
    (193, "easy", "O Christmas Tree"), (194, "easy", "What Child Is This"),
    (195, "harder", "All I Want For Christmas"), (196, "harder", "The Christmas Waltz"),
    (197, "difficult", "'Zat You, Santa Claus"), (198, "easy", "Twelve Days"),
    (199, "easy", "Hark! The Herald"), (200, "easy", "O Holy Night"),
    (201, "harder", "The Nutcracker"),
]

# Charted, but the peak misleads: a standard everyone knows that only ever
# charted low, or a famous song in a recent cover that barely registered.
CHARTED_FIXES = [
    (7, "harder", "Run Rudolph Run"), (17, "harder", "The Christmas Song"),
    (28, "harder", "Santa Baby"), (79, "easy", "Wonderful Christmastime"),
    (89, "easy", "Happy Xmas"), (108, "harder", "Mele Kalikimaka"),
    (119, "easy", "Blue Christmas"), (121, "easy", "Here Comes Santa Claus"),
    (125, "harder", "Baby It's Cold Outside"), (130, "easy", "I Saw Mommy Kissing"),
    (133, "harder", "Last Christmas"), (140, "easy", "This Christmas"),
    (148, "harder", "The Prayer"), (157, "easy", "You're A Mean One"),
    (164, "easy", "Winter Wonderland"), (167, "easy", "Linus And Lucy"),
    (176, "easy", "(There's No Place Like) Home"), (185, "easy", "Baby, It's Cold Outside"),
    (186, "easy", "I'll Be Home For Christmas"), (191, "harder", "Adeste Fideles"),
]


def main(apply_changes):
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows, fields = list(reader), reader.fieldnames
    by_num = {r["#"]: r for r in rows}

    changes, mismatches = [], []
    for num, level, prefix in UNCHARTED + CHARTED_FIXES:
        row = by_num.get(str(num))
        if row is None:
            mismatches.append(f"row {num} not found")
            continue
        if not row["Clean Title"].startswith(prefix):
            mismatches.append(
                f"row {num}: expected title to start {prefix!r}, "
                f"found {row['Clean Title']!r}"
            )
            continue
        changes.append((row, level))

    if mismatches:
        print("ABORTED — the CSV does not match this script:", file=sys.stderr)
        for m in mismatches:
            print(f"  {m}", file=sys.stderr)
        return 1

    for row, level in changes:
        row["Difficulty"] = level

    counts = {"easy": 0, "harder": 0, "difficult": 0}
    for row in rows:
        peak = row["Peak (Hot 100)"].strip()
        level = row["Difficulty"] or (
            "easy" if peak and int(float(peak)) <= 5
            else "harder" if peak and int(float(peak)) <= 15
            else "difficult"
        )
        counts[level] += 1

    print(f"{len(changes)} rows assigned "
          f"({len(UNCHARTED)} uncharted, {len(CHARTED_FIXES)} charted corrections)")
    print(f"resulting mix: easy {counts['easy']}, harder {counts['harder']}, "
          f"difficult {counts['difficult']}")

    if not apply_changes:
        print("\ndry run — pass --apply to write")
        return 0

    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    print(f"written to {CSV_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main("--apply" in sys.argv))
