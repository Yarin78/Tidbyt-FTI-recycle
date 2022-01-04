load("render.star", "render")
load("http.star", "http")
load("encoding/json.star", "json")
load("encoding/base64.star", "base64")
load("time.star", "time")
load("cache.star", "cache")

RECYCLE_URL = "https://webapp.ftiab.se/Code/Ajax/StationHandler.aspx/GetStationMaintenance"

STATION_ID = 10152

MONTHS = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "maj": 5,
    "jun": 6,
    "juni": 6,
    "jul": 7,
    "juli": 7,
    "aug": 8,
    "sep": 9,
    "sept": 9,
    "okt": 10,
    "nov": 11,
    "dec": 12
}

CACHE_KEY = "recycle_status"
CACHE_TTL_SECONDS = 15 * 60

SELECTED_CATEGORIES = ["Carton", "Papers", "Plastic", "ColoredGlass"]
#SELECTED_CATEGORIES = ["ColoredGlass", "Glass", "Metal", "Cleaning"]

CATEGORIES = {
    "Cleaning": "Städning",
    "ColoredGlass": "Färgat glas",
    "Glass": "Ofärgat glas",
    "Carton": "Kartong",
    "Metal": "Metall",
    "Plastic": "Plast",
    "Papers": "Papper",
}

# Generate with: for x in images/*.png; do echo $x; base64 $x; done
ICONS = {
    "Carton": base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAH1JREFUOE9jZKAQMOLT//+27X+QPKPqYUZkNrIenAaANIA0ghTjYoMNR3cBzCZifAayAKsBMJuxGQJzDYweBAbg8zOyV5DVwWIFHgbIoYzsb3T/okcrSiASE/rINmMNRGwuweYKDC/AnD34DUBPWBgpkVBAYkuheHMjMfkBAAmAtBEtWcCTAAAAAElFTkSuQmCC"),
    "Cleaning": base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAGxJREFUOE+9ksEOwCAIQ/XHOfDjMxyasA6R6KIno/JoK70drp7Vq+qDexEJ34aHvpAbMOgFyApnoNRCJZ5/FcCC+azsTWGoYBtgROu8Avif+ITI0gFjKAK+D0gHCbJ8DmzhHmA2hSUFlRHGmwHxupQR+KqqUwAAAABJRU5ErkJggg=="),
    "ColoredGlass": base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAEdJREFUOE9jZKAQMOLTL7O+9z9I/klgMU51w9kAmP9hYYQrHLCGAbpmfIaMGsDAQNswgEUdviSN0wXo8Q4yBFtaoI0XSMnhANchQBFfXZ17AAAAAElFTkSuQmCC"),
    "Glass": base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAE1JREFUOE9jZKAQMOLTL7O+9z9I/klgMU51w9kAkP9hfkdmo4cZ1jDApgGXIaMGMDDgDQPklEhyICInYXxJmnaxgC2TYctUeDMTMTkdAF3nYBEGP4GBAAAAAElFTkSuQmCC"),
    "Metal": base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAHJJREFUOE9jZKAQMFKon2HUAAbSwyCpsOo/LODn9bcxkhSIyJpBhmA1AN0GmG0wcZAm5KiHc7ApwGYjeroBGwBSiG4yskJctoPUwA1ADhh0Z8P8iy3VYhiAK2njciFGGGAzAJ/3MKIRVyzgchlJ6QCbIQA/nTQRnuhvJwAAAABJRU5ErkJggg=="),
    "Papers": base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAFhJREFUOE9jZKAQMOLVX7/vP1b5Rie4PtwGgDSDFMJomElofOwGICsi2QACGtBdhOoCdM0gZ5PkAiICjXQXoEcD3kDE5oVRAzBTMu0DkZjcSVRmIsYgoBoASuZaETVhny8AAAAASUVORK5CYII="),
    "Plastic": base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAExJREFUOE9jZKAQMOLSP0Wr7T9ILudaFU41IPlBagDM+TDv4fMGVi+gG4AvLDAMwKYZn0voYwAoDEAuwxYWRLlg4A0Y+ECkrwtIzd0AyudEEX92dL4AAAAASUVORK5CYII="),
}

def time_ago(dt_str):
    # dt_str is in format "3 jan kl 10:50"
    parts = dt_str.split(' ')
    h,m = parts[3].split(':')

    # Since we don't know year, assume it's this year
    year = time.now().year
    month = MONTHS[parts[1]]
    if month > time.now().month:
        # However, if the month is in the future, it must have been the previous year
        year -= 1

    last_time = time.time(
        year=year,
        month=month,
        day=int(parts[0]),
        hour=int(h),
        minute=int(m),
        location="Europe/Stockholm"
    )

    duration_hours = int((time.now() - last_time).hours)
    if (duration_hours < 0):
        duration_hours = 0

    if duration_hours < 72:
        s = "%dh" % duration_hours
    else:
        s = "%dd" % (duration_hours / 24)
    if len(s) == 2:
        s = " %s" % s
    return s

def get_status():
    status_json = cache.get(CACHE_KEY)
    if status_json != None:
        print("Hit! Displayed cached data")
    else:
        print("Miss! Calling API.")
        rep = http.post(RECYCLE_URL, json_body={"stationId": STATION_ID})
        if rep.status_code != 200:
            fail("Failed to get recycle data - status %d", rep.status_code)
        status_json = rep.json()["d"]

        cache.set(CACHE_KEY, status_json, ttl_seconds=CACHE_TTL_SECONDS)

    return json.decode(status_json)

def get_fake_status():
    return {
        "LastCleaning": "3 jan kl 11:34",
        "NextCleaning": "5 jan",
        "LastColoredGlass": "29 dec kl 14:06",
        "NextColoredGlass": "*",
        "LastGlass": "29 dec kl 14:06",
        "NextGlass": "*",
        "LastCarton": "4 jan kl 13:29",
        "NextCarton": "4 jan",
        "LastMetal": "3 jan kl 10:07",
        "NextMetal": "5 jan",
        "LastPlastic": "3 jan kl 10:50",
        "NextPlastic": "4 jan",
        "LastPapers": "3 jan kl 16:40",
        "NextPapers": "*"
    }

def main():
    status = get_status()

    for k, v in CATEGORIES.items():
        print("{}: {}".format(v, time_ago(status["Last{}".format(k)])))

    info = []

    for cat in SELECTED_CATEGORIES:
        info.append(render.Row(children=[
            render.Image(src=ICONS[cat]),
            render.Text(time_ago(status["Last{}".format(cat)]))], cross_align="center"))

    if len(info) != 4:
        fail("Exactly 4 categories should be selected")

    return render.Root(
        child = render.Column(
            children = [
                render.Row(
                    children = [
                        render.Box(child=info[0], width=32, height=16),
                        render.Box(child=info[1], width=32, height=16)
                    ]
                ),
                render.Row(
                    children = [
                        render.Box(child=info[2], width=32, height=16),
                        render.Box(child=info[3], width=32, height=16)
                    ]
                )
            ]))

