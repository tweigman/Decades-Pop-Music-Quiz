#!/usr/bin/env python3
"""Fill the Difficulty column for categories/holiday.csv.

    python3 classify_holiday.py [--apply]

Chart peak is a bad difficulty proxy here: most holiday songs never made the
Hot 100, so they all default to 'difficult' -- including Silent Night. These
are hand assignments.

The rule, given that naming *either* the song or the artist scores:

  easy       the song is a standard nearly anyone can name, in a recording
             people have actually heard (Bing Crosby, Nat King Cole, the
             Peanuts soundtrack, Brenda Lee)
  harder     a famous song in an unfamiliar arrangement (the Spotify Singles
             covers), a big-artist modern holiday single, a UK standard that
             never crossed over, or a well-known instrumental
  difficult  recent album cuts and one-off singles with no cultural foothold

Entries are keyed by Spotify track id, not row number, so deduplicating or
reordering the CSV cannot silently shift assignments onto the wrong songs.
Anything listed here but absent from the CSV is reported rather than ignored.
"""

import csv
import sys

CSV_PATH = "categories/holiday.csv"

# Songs with no Hot 100 entry, which would otherwise all be 'difficult'.
UNCHARTED = [
    ("5mi0HQrZMhRb2MRdFiUP6v", "difficult"),  # santa doesn’t know you like i do
    ("1LmkdWSxjCV7wKTPsCvYWN", "harder"),  # Winter Wonderland - Spotify Single
    ("7L3OGWgJMQdXSbY3zgUt1Q", "harder"),  # O Holy Night - Spotify Singles Hol
    ("7yogx3TwxGwSxO2QITsT2q", "harder"),  # A Nonsense Christmas
    ("5WinrM87TaUBLxOOCeACBi", "difficult"),  # Coming Home This Christmas
    ("0YWUHZPJVg4iujddsJDwhM", "harder"),  # My Only Wish (This Year)
    ("5sZR7OC7uHArUWvNyunS3T", "difficult"),  # Christmas Lights - Spotify Singles
    ("0UOG0zUn7t8m8QcxfzR7AH", "difficult"),  # Merry Christmas, Please Don't Call
    ("38fhq0EiSzlIwv20tHNGss", "harder"),  # Blue Christmas
    ("7IUlxfabTQQpp0VsRIU8sa", "difficult"),  # Just For Christmas
    ("2ZAEbbKPNf1Wv1fifB2nyd", "difficult"),  # You Deserve It All
    ("54H84HFq1hUDEOcYxbTjrL", "harder"),  # Christmas (Baby Please Come Home)
    ("5rukTp7yZJgpIKO7eDuwZg", "difficult"),  # old fashioned christmas
    ("1knrvScmRb6ZCPPsBzDHcy", "difficult"),  # 1 Wish
    ("0Nzivfp90nH1WCPAMm7PV4", "harder"),  # River
    ("0KtV18BLmyIOYHCSISmVl9", "difficult"),  # canal street
    ("7Kr4PZ2XFbaQ28sA1ZeIKa", "difficult"),  # Officially Christmas
    ("7KeHUoqosk3skfRbICgHnS", "difficult"),  # secret santa
    ("2CySXalJw1XI1BmxOaZIRl", "difficult"),  # promise to me (he’s the one)
    ("0jPnNZS9IJ0awbpFLZr3EY", "harder"),  # Have Yourself a Merry Little Chris
    ("2Gu7uiGb7ZDOQ1O9jZJQEH", "harder"),  # This Christmas
    ("6JJ4W13A4Q5yeK4g6OROmg", "difficult"),  # Not Just On Christmas
    ("0nhpTFbJ3uX4qqL9qaQj5B", "difficult"),  # Gifts For Me
    ("2gciS7UJjv59l7608DFGNl", "harder"),  # Driving Home for Christmas - Spoti
    ("6TXAjof8V0Gr4zFoY00zHR", "harder"),  # You’re A Mean One, Mr. Grinch
    ("3bq7dXN7arTdaq8mmKXxob", "difficult"),  # Love to Keep Me Warm
    ("3emyfamOMxgrus8oZQh6Mx", "difficult"),  # Under the Tree
    ("6yDfTEbIVwCV40G74x9yY8", "difficult"),  # I Wanna Be Your Christmas Tree
    ("1QNPTNaw67BanVtwXKIX1a", "difficult"),  # December 25th
    ("0YupMLYOYz6lZDbN3kRt7A", "difficult"),  # I'll Be Home
    ("78pn8k7RogKo2oxl0DyX6d", "harder"),  # One More Sleep
    ("4v9WbaxW8HdjqfUiWYWsII", "harder"),  # Merry Christmas, Happy Holidays
    ("0XYALktGbnHJ1TdW0Oz5KN", "difficult"),  # Merry Christmas, i miss you
    ("5BIAqf246BYNH3YA8PQ9qg", "difficult"),  # Scotland In The Snow
    ("065CI94mu3IZwqPU4BX4Cb", "difficult"),  # Christmas the Whole Year Round
    ("0sOLCWKwwxMFa56FlHw1Dv", "harder"),  # Santa Claus Is Coming To Town
    ("5zqzV32ifPJ9XhqfyjYrBy", "difficult"),  # Dear Santa
    ("3N7TTZ7VQFpSTl0jb5gb87", "difficult"),  # Home to Me
    ("1QLZKzC2pjP4ySf4ALrNhm", "difficult"),  # Christmas Without You
    ("7enVhl0fuHvQ4ErXvAXYIH", "harder"),  # Sleigh Ride
    ("3UwzSVO6CzZRGFgyeuM9qf", "difficult"),  # Winter Song
    ("0JnT4HGgwKZspTP55W7EaN", "difficult"),  # You For Christmas
    ("1wmPiEINk0ig3Q0Cit7Anh", "difficult"),  # I Don't Need It To Be Christmas At
    ("1yepCSPoxirpHDK1580Eq5", "difficult"),  # Hot in December
    ("0w8ZIZZKew8iWefjNlTfnF", "difficult"),  # Christmas Magic
    ("6RS6rcjnWrdfVuu2U2W2dj", "difficult"),  # Make It To Christmas
    ("2eesOzilqjDBePl9nSiUoz", "difficult"),  # Please Santa Please
    ("29WqxdrhcCzS63xaZkhKmC", "harder"),  # Jingle Bell Rock -Spotify Singles 
    ("06b5RW4WE4wa0rr62PMA7s", "difficult"),  # Back Home For Christmas
    ("1N1ZpYUJc9fwrqk53FGgWv", "harder"),  # Santa's Coming for Us
    ("4G0YpYB1Ullb5rgJeJoMcP", "harder"),  # I'll Be Home For Christmas - Recor
    ("2TaQZIxvt9TVfNqXe5A1ae", "difficult"),  # Kissing In the Cold
    ("1O2ymfIOPUz7RLzjDCnCWv", "harder"),  # Christmas Wrapping
    ("1rRb8IFx7OYqlZnt6ag7cP", "easy"),  # Silent Night
    ("5MPd7GzOkGRoFBaSqmqiSL", "harder"),  # What Christmas Means To Me
    ("7hTFtyYGqtJBJAHVv1oXQ9", "difficult"),  # Hot Cocoa
    ("6fE2Kjwd5Fh2xF9IeuiOY4", "difficult"),  # Don't Give Your Heart Away for Chr
    ("4dFtIGQBrYjiskk7fN5Wmx", "difficult"),  # Glittery - From The Kacey Musgrave
    ("7o4HtESXicUqk3oRqngIsS", "harder"),  # 8 Days of Christmas
    ("2Ysi49tRdVH74d1Cnc4o94", "harder"),  # Man With The Bag
    ("6brLwOYFXw7rkGOcLntcPZ", "harder"),  # merry christmas darling
    ("4tHqQMWSqmL6YjXwsqthDI", "easy"),  # Carol of the Bells
    ("6s2wpWPFPAgKg2LXxi1Oee", "easy"),  # Santa Claus Is Comin' to Town
    ("2FPfeYlrbSBR8PwCU0zaqq", "easy"),  # Have Yourself A Merry Little Chris
    ("6sBWmE23q6xQHlnEZ8jYPT", "easy"),  # Step Into Christmas
    ("6iO6ZLKaJF13fuF5HUFSEM", "harder"),  # O Come All Ye Faithful - Spotify S
    ("06Pfxmp9TtC2H00apclouT", "easy"),  # Christmas Time Is Here - Vocal
    ("2TE4xW3ImvpltVU0cPcKUn", "harder"),  # Merry Christmas Everyone
    ("4soJpnUFA0SPs7XTi6QIVp", "harder"),  # Fairytale of New York (feat. Kirst
    ("13XMz3rpVYITzjFIsSYlZ1", "harder"),  # What Christmas Means to Me (feat. 
    ("7zqv6rEbwXksyE0tk9RCO1", "harder"),  # Where Are You Christmas?
    ("0rHToGels2lt8Y0mCYoF90", "easy"),  # Deck The Hall
    ("7v6DvsyQHmsQQhmVDmrnZg", "easy"),  # Ave Maria
    ("4kKdvXD0ez7jp1296JmAts", "easy"),  # Let It Snow! Let It Snow! Let It S
    ("47otoIkhx3fkdivEXL5OB6", "easy"),  # Rudolph The Red-Nosed Reindeer
    ("2AEjZQblAZwdbcYA1qiexM", "harder"),  # Thank God It's Christmas
    ("0uTVChzibEWKrXojPaJ9y1", "harder"),  # Hard Candy Christmas
    ("3sBnSBnzpEYKpJYGsAIbup", "harder"),  # Christmas Eve / Sarajevo 12/24 - I
    ("5aDoUmxBsbdpS16alksb5Z", "easy"),  # Do You Hear What I Hear?
    ("2IuUMx3uxxJAHcH41aYtn0", "easy"),  # Winter Wonderland
    ("65irrLqfCMRiO3p87P4C0D", "easy"),  # Frosty The Snowman
    ("3Z3QhZAZpqwZa1phsbQ3JZ", "harder"),  # Driving Home for Christmas
    ("6ImuFqEAZf9dkpuYahSr0K", "difficult"),  # We Wish You The Merriest
    ("3PIDciSFdrQxSQSihim3hN", "harder"),  # Christmas (Baby Please Come Home)
    ("0OdTRhhGt8aq4UXh67CKQg", "harder"),  # Someday At Christmas
    ("4ukUoXLuFzMixyZyabSGc4", "easy"),  # Sleigh Ride
    ("1mH6tZC6iXIHPI6EixCwxw", "harder"),  # I Wish It Could Be Christmas Every
    ("41onDks2UPbyjer5fMeUWf", "harder"),  # Christmas In Hollis
    ("5fhjN7E4rV0GqsRSQBsWeo", "easy"),  # The First Noël (with Faith Hill)
    ("7n7VsX3sv66znBwA8b5uhp", "easy"),  # Here Comes Santa Claus (Right Down
    ("65YvxGS3GVnqDFjLCt5HUV", "easy"),  # Joy To The World
    ("5DMItYJluCFc7YtFdP4aXo", "difficult"),  # Lonely This Christmas
    ("6pVW5LRWgeLaHudxauOTJU", "easy"),  # Jingle Bell Rock
    ("5P8Xvy5tzhmfyfA6GplQ8h", "harder"),  # I Want a Hippopotamus for Christma
    ("6syO6UTl8QiiWADJy3Uy2d", "easy"),  # Santa Claus Is Coming To Town
    ("030mot3ZKR3oskfMsqDB2R", "easy"),  # Have Yourself A Merry Little Chris
    ("6Uekkm0MOVT4WznQy0ktVR", "easy"),  # God Rest Ye Merry Gentlemen
    ("2QWKbE6GpWhRtlbRwcP7g8", "difficult"),  # Cool Yule
    ("7GNsHkiYPcQQjvhTiILFUL", "difficult"),  # A Marshmallow World
    ("7azp0ySqPkkXHi9M9aeg3T", "harder"),  # (Everybody's Waitin' For) The Man 
    ("7n5m8nDAnyXo81tr4B3Bcw", "easy"),  # Frosty the Snowman
    ("11Z7sdkpC5IaaydoIvDn74", "harder"),  # Caroling, Caroling
    ("0z5HSQGWgnjdNvwbOmhB2w", "harder"),  # Merry Christmas Darling - Remix
    ("7ehhnVu3JUWMaSJzY1zC4k", "easy"),  # Silver Bells
    ("4YhY2qHdBmSX33uj8ms0oq", "easy"),  # O Tannenbaum
    ("1KIJSvzRZzo8ehDTPOXKru", "harder"),  # I've Got My Love To Keep Me Warm
    ("0H1zX27yxoDrsrQA1hk5Uq", "easy"),  # O Come All Ye Faithful
    ("7qLTpTd1Txpo8Vd84yci7u", "easy"),  # My Favourite Things
    ("1DvjCIefxg1YsdG3ETROph", "easy"),  # The First Noël
    ("0pAT3JUEjIiqUkwxE0vbBQ", "easy"),  # The Little Drummer Boy
    ("4Fpd1N7fcbRLnHbsk5D4Ye", "harder"),  # Mary's Boy Child
    ("6Ai7PiAjnb4eIiC05By0i4", "easy"),  # O Little Town of Bethlehem
    ("53cumdNGYE6NFmGL0zHvx7", "harder"),  # Mistletoe And Holly
    ("19NdiithlwC8EfytiHVk7a", "harder"),  # What Are You Doing New Year's Eve?
    ("07QfuFPazJYuzRtcWW0U2y", "easy"),  # Silent Night
    ("1Kcy7qSbf6un30zIkxGVew", "easy"),  # Here We Come a-Caroling / We Wish 
    ("2VsCE6ui7N4IRzGIGT7Di8", "easy"),  # O Christmas Tree (feat. Count Basi
    ("6OJdXv1Q5OdLgYolFEunJ4", "easy"),  # What Child Is This/The Holly And T
    ("4xXMJbzVQSCyprr4PG5sBj", "harder"),  # All I Want For Christmas (Is My Tw
    ("6G7QhTqDsP5vIdLQTYXXOU", "harder"),  # The Christmas Waltz
    ("0SD2UtunDGrX7OIElVr87B", "difficult"),  # 'Zat You, Santa Claus?
    ("0cAhE2iDJApegDnVRx6fCK", "easy"),  # Twelve Days Of Christmas
    ("4BgkhT5HythXhIBqU2WvhX", "easy"),  # Hark! The Herald Angels Sing/It Ca
    ("2aQkTUbJUHk3F6nMipZLbz", "easy"),  # O Holy Night
    ("7iHKfYLLT1bjZUXO4IC61S", "harder"),  # The Nutcracker, Op. 71, TH 14, Act
]

# Charted, but the peak misleads: a standard everyone knows that only ever
# charted low, or a famous song in a recent cover that barely registered.
CHARTED_FIXES = [
    ("6pheMGrfMwwnypqafU7d4k", "harder"),  # Run Rudolph Run - Spotify Singles 
    ("4WRb5qAPnvMbUIrnjLaggC", "harder"),  # The Christmas Song
    ("4jHl6jgzZOnS4nGamPZ1Uk", "harder"),  # Santa Baby
    ("1SV1fxF65n9NhRHp3KlBuu", "easy"),  # Wonderful Christmastime
    ("27RYrbL6S02LNVhDWVl38b", "easy"),  # Happy Xmas (War Is Over)
    ("04vLj9QUXoKdRlsp3gkURo", "harder"),  # Mele Kalikimaka (Merry Christmas)
    ("3QiAAp20rPC3dcAtKtMaqQ", "easy"),  # Blue Christmas
    ("25leEEaz1gIpp7o21Fqyjo", "easy"),  # Here Comes Santa Claus (Right Down
    ("0Ie5uiv54KgCr7P4sYDTHl", "harder"),  # Baby It's Cold Outside (with Micha
    ("15sxLiiChE5dCW3Y756oas", "easy"),  # I Saw Mommy Kissing Santa Claus
    ("5xDrO9DEDJGUQGfyoHvgDJ", "harder"),  # Last Christmas
    ("38xhBO2AKrJnjdjVnhJES6", "easy"),  # This Christmas
    ("6zlY4xmlgqvn4LxjzoS2mz", "harder"),  # The Prayer
    ("4qP2V09IpTct5A1ZSnr1zh", "easy"),  # You're A Mean One, Mr. Grinch
    ("12YAgUbl6Uk9E7fzopF4Ji", "easy"),  # Winter Wonderland
    ("33EcmYsTQVIGRGnGPOfTwu", "easy"),  # Linus And Lucy
    ("2GapxG7BxK55ihQRAlR39e", "easy"),  # (There's No Place Like) Home for t
    ("4MrfQL4TYQXJBlZYpAHTuE", "easy"),  # Baby, It's Cold Outside
    ("4lftz0V8DZhWSVtL4GrzMH", "easy"),  # I'll Be Home For Christmas
    ("04DYwFIKeq2Bkn9aqSI9PC", "harder"),  # Adeste Fideles
]


def main(apply_changes):
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows, fields = list(reader), reader.fieldnames
    by_id = {r["URL"].rstrip("/").split("/")[-1].split("?")[0]: r for r in rows}

    changes, missing = [], []
    for tid, level in UNCHARTED + CHARTED_FIXES:
        row = by_id.get(tid)
        if row is None:
            missing.append(tid)
            continue
        changes.append((row, level))

    if missing:
        print(f"{len(missing)} assigned track(s) are no longer in the CSV:",
              file=sys.stderr)
        for tid in missing:
            print(f"  {tid}", file=sys.stderr)

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

    print(f"{len(changes)} rows assigned of {len(rows)} "
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
