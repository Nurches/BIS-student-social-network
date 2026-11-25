"""Week 13 (FR-08): event posters, uploaded in /admin and shown in the app.

Akbota's threats and what answers them:

* a disguised file (an .exe renamed .jpg, an SVG with a script): the type is
  read from the first bytes (magic numbers), never from the name or the
  Content-Type; only JPEG, PNG and WebP pass, and Pillow must decode it;
* a huge file: 413 above 2 MB, before the body is even read in full
  (main.BodySizeLimit); a small file that expands to a giant picture (a
  "decompression bomb") is refused above 40 megapixels;
* GPS and other EXIF data in a phone photo: every upload is decoded and saved
  again, which keeps the pixels only; the photo is turned upright first;
* an upload to another community's event: same rule as editing it (owner or
  moderator), checked in services/admin_panel.py;
* an inappropriate poster: a moderator removes any poster.

The image is kept in PostgreSQL (table event_poster): the free Render disk is
wiped on every deploy.
"""

import io
import warnings
from dataclasses import dataclass

from PIL import Image, ImageOps, UnidentifiedImageError

from ..db import Conn
from ..errors import ApiError

MAX_POSTER_BYTES = 2 * 1024 * 1024  # FR-08: 2 MB, also a CHECK in the schema
MAX_PIXELS = 40_000_000  # larger = refused as a decompression bomb
MAX_SIDE = 1600  # stored size: enough for a phone screen at 3x
JPEG_QUALITY = 85

_FORMATS = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}


@dataclass(frozen=True)
class Poster:
    mime: str
    data: bytes
    width: int
    height: int


def sniff(data: bytes) -> str | None:
    """The image type by its first bytes, or None if it is not one we accept."""
    if data.startswith(b"\xff\xd8\xff"):
        return "JPEG"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "PNG"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "WEBP"
    return None


def process(data: bytes) -> Poster:
    """Checks an upload and re-encodes it. Raises ApiError 413/415/422."""
    if len(data) > MAX_POSTER_BYTES:
        raise ApiError(413, "poster_too_large")
    if not data:
        raise ApiError(415, "unsupported_poster_type")
    declared = sniff(data)
    if declared is None:
        raise ApiError(415, "unsupported_poster_type")

    try:
        with warnings.catch_warnings():
            # Pillow only warns between MAX_PIXELS and 2x; make it an error.
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            image = Image.open(io.BytesIO(data))
            # Phone cameras save some JPEGs as MPO (several pictures in one file).
            if image.format != declared and not (declared == "JPEG" and image.format == "MPO"):
                raise ApiError(415, "unsupported_poster_type")
            if image.width * image.height > MAX_PIXELS:
                raise ApiError(422, "poster_unreadable")
            image.load()
            image = ImageOps.exif_transpose(image)  # upright, before EXIF is dropped
    except ApiError:
        raise
    except (
        UnidentifiedImageError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
        OSError,
        SyntaxError,
        ValueError,
    ) as exc:
        raise ApiError(422, "poster_unreadable") from exc

    image.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
    poster = _encode(image, declared)
    if len(poster.data) > MAX_POSTER_BYTES:
        # A noisy PNG can stay big after resizing: fall back to JPEG.
        poster = _encode(image, "JPEG")
    return poster


def _encode(image: Image.Image, fmt: str) -> Poster:
    """Saves the pixels only: no EXIF, GPS, comments or colour profile."""
    has_alpha = image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info)
    out = io.BytesIO()
    if fmt == "JPEG":
        if has_alpha:
            background = Image.new("RGB", image.size, (255, 255, 255))
            background.paste(image.convert("RGBA"), mask=image.convert("RGBA").getchannel("A"))
            clean = background
        else:
            clean = image.convert("RGB")
        clean.save(out, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
    elif fmt == "PNG":
        clean = image.convert("RGBA" if has_alpha else "RGB")
        clean.save(out, "PNG", optimize=True)
    else:
        clean = image.convert("RGBA" if has_alpha else "RGB")
        clean.save(out, "WEBP", quality=JPEG_QUALITY, method=4)
    return Poster(_FORMATS[fmt], out.getvalue(), clean.width, clean.height)


def load(conn: Conn, event_id: int) -> dict:
    """The poster of a published or cancelled event, for GET without a token:
    a poster is an advertisement, like the event itself. A draft's is hidden."""
    row = conn.execute(
        """
        SELECT ep.mime, ep.data, ep.uploaded_at
        FROM event_poster ep
        JOIN event e     ON e.event_id = ep.event_id
        JOIN community c ON c.community_id = e.community_id
        WHERE ep.event_id = %s AND e.status IN ('published', 'cancelled')
          AND e.deleted_at IS NULL AND c.deleted_at IS NULL
        """,
        (event_id,),
    ).fetchone()
    if row is None:
        raise ApiError(404, "poster_not_found")
    return row
