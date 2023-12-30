import string
import time
import random
from flask import Flask, request

app = Flask(__name__)


def random_int(max=100000):
    return random.randint(1, max)


def random_string(length: int = 100, alphabet=string.ascii_letters):
    return "".join([random.choice(alphabet) for _ in range(length)])


def random_yt_channel():
    return random_string(32)


def random_yt_video():
    return random_string(16)


def thumbnail_for(id):
    return f"http://example-proxey.com/vi/{id}/hq720.jpg?host=localhost:8080"


def channel_for(id):
    return f"/channel/{id}"


def random_stream():
    channel_id = random_yt_channel()
    youtube_id = random_yt_video()
    return {
        "url": f"/watch?v={youtube_id}",
        "type": "stream",
        "title": random_string(),
        "uploaderUrl": channel_for(channel_id),
        "thumbnailUrl": thumbnail_for(channel_id),
        "uploaderName": random_string(),
        "uploaderAvatar": None,
        "uploadedDate": "1 day ago",
        "shortDescription": "amogus",
        "duration": random_int(999),
        "views": 1337,
        "uploaded": int(time.time()),
        "uploaderVerified": False,
        "isShort": False,
    }


@app.route("/search", methods=["GET"])
def search_route():
    return {
        "items": [random_stream() for _ in range(10)],
        "nextpage": "",
        "suggestion": None,
        "corrected": False,
    }


@app.route("/channel/<channel_id>", methods=["GET"])
def channel_route(channel_id):
    return {
        "id": channel_id,
        "name": random_string(),
        "avatarUrl": random_string(),
        "bannerUrl": random_string(),
        "description": random_string(),
        "nextpage": None,
        "subscriberCount": random_int,
        "tabs": [],
        "relatedStreams": [random_stream() for _ in range(10)],
    }


@app.route("/playlists/<playlist_id>", methods=["GET"])
def playlist_route(playlist_id):
    uploader_id = random_yt_channel()
    return {
        "name": random_string(),
        "thumbnailUrl": thumbnail_for(playlist_id),
        "description": random_string(),
        "bannerUrl": "",
        "nextpage": "",
        "uploader": random_string(),
        "uploaderUrl": channel_for(channel_id),
        "uploaderAvatar": random_string(),
        "videos": 10,
        "relatedStreams": [random_stream() for _ in range(10)],
    }


@app.route("/_subtitles", methods=["GET"])
def subtitles_route():
    return random_string()


@app.route("/streams/<stream_id>", methods=["GET"])
def stream_route(stream_id):
    channel_id = random_yt_channel()
    return {
        "title": random_string(),
        "description": random_string(),
        "uploader": random_string(),
        "uploaderUrl": channel_for(channel_id),
        "thumbnailUrl": thumbnail_for(stream_id),
        "hls": f"/_hls/{stream_id}",
        "dash": None,
        "lbryId": None,
        "category": random_string(),
        "visibility": "public",
        "duration": random_int(999),
        "views": random_int(99999),
        "likes": random_int(99999),
        "dislikes": random_int(99999),
        "audioStreams": [],
        "videoStreams": [
            {
                "url": "https://pipedproxy-cdg.kavin.rocks/videoplayback?ei=hCuPZZvjEKKb1sQP0OC1uAk&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1000&id=o-AG7Nmaf6EXgzgAt5390RzIn-XTqatVAr8NpYlYwh_iNg&itag=22&source=youtube&requiressl=yes&xpc=EgVo2aDSNQ%3D%3D&mh=BJ&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7yn7l&ms=au%2Crdu&mv=m&mvi=2&pcm2cms=yes&pl=54&initcwndbps=1346250&spc=UWF9f7LBLcjFGRuqODmfE501Su-YR1s&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=2217.830&lmt=1703842656982265&mt=1703881261&fvip=3&fexp=24007246&c=ANDROID&txp=4432434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cxpc%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AJfQdSswRgIhAJ7khi6JalJgastKPtVQdFbNpuj9_iDQmDJ4kv3v6uqRAiEAnwvcvKY6EyX4r6pKpfU1NRZAoPLvYm8fOZLqemZw7JM%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpcm2cms%2Cpl%2Cinitcwndbps&lsig=AAO5W4owRgIhAMaz3hBTB40sc__XVL8Y6h6foz1p7a01dcEXV0SsK308AiEA5ykExoRbwQ6fK63Fab1stv2OaYZoM4sDk-8JkRXvMKY%3D&cpn=9SbzDQn4uwJyNS36&host=rr2---sn-oxunxg8pjvn-gxjl.googlevideo.com",
                "format": "MPEG_4",
                "quality": "720p",
                "mimeType": "video/mp4",
                "codec": None,
                "audioTrackId": None,
                "audioTrackName": None,
                "audioTrackType": None,
                "audioTrackLocale": None,
                "videoOnly": False,
                "itag": 22,
                "bitrate": 0,
                "initStart": 0,
                "initEnd": 0,
                "indexStart": 0,
                "indexEnd": 0,
                "width": 0,
                "height": 0,
                "fps": 0,
                "contentLength": -1,
            }
        ],
        "relatedStreams": [],
        "subtitles": [
            {
                "url": f"http://localhost:8080/_subtitles?v={stream_id}",
                "mimeType": "text/vtt",
                "name": "English",
                "code": "en",
                "autoGenerated": False,
            }
        ],
        "livestream": False,
        "proxyUrl": "kldsjfl",
        "chapters": [],
        "previewFrames": [],
    }


@app.route("/trending", methods=["GET"])
def trending():
    videos = []
    for _ in range(10):
        videos.append(random_stream())
    return videos


@app.route("/api/skipSegments", methods=["GET"])
def sponsorblock_sgements():
    return [
        {
            "category": "sponsor",
            "actionType": "skip",
            "segment": [90.343, 132.37],
            "UUID": random_string(),
            "videoDuration": random_int(999),
            "locked": 1,
            "votes": 10,
            "description": random_string(),
        }
        for _ in range(random.randint(1, 10))
    ]
