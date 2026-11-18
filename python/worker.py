"""Persistent RGB detector. stdout is exclusively a bounded packet-4 protocol."""
import contextlib
import json
import os
import struct
import sys

MAX_PACKET = 8 * 1024 * 1024

def read_exact(stream, size):
    data = bytearray()
    while len(data) < size:
        chunk = stream.read(size - len(data))
        if not chunk:
            if not data:
                return None
            raise ValueError("truncated packet")
        data.extend(chunk)
    return bytes(data)


def read_packet(stream):
    prefix = read_exact(stream, 4)
    if prefix is None:
        return None
    size = struct.unpack(">I", prefix)[0]
    if not 0 < size <= MAX_PACKET:
        raise ValueError("invalid packet size")
    body = read_exact(stream, size)
    if body is None:
        raise ValueError("truncated packet")
    return body


def decode_frame(body):
    if len(body) < 4:
        raise ValueError("missing header")
    size = struct.unpack(">I", body[:4])[0]
    if not 0 < size <= 4096 or len(body) < 4 + size:
        raise ValueError("invalid header")
    header = json.loads(body[4:4 + size])
    w, h = header['width'], header['height']
    if type(w) is not int or type(h) is not int or not (1 <= w <= 1280 and 1 <= h <= 1280):
        raise ValueError("invalid dimensions")
    pixels = body[4 + size:]
    if len(pixels) != w * h * 3:
        raise ValueError("invalid RGB payload")
    return header, pixels


def send(stream, value):
    payload = json.dumps(value, allow_nan=False, separators=(',', ':')).encode()
    if len(payload) > MAX_PACKET:
        raise ValueError("oversize response")
    stream.write(struct.pack(">I", len(payload)) + payload)
    stream.flush()


def main():
    output = sys.stdout.buffer
    with contextlib.redirect_stdout(sys.stderr):
        import numpy as np
        import torch
        from ultralytics import YOLO
        torch.set_num_threads(int(os.environ.get('DETECTION_THREADS', '2')))
        model = YOLO(sys.argv[1])
    send(output, {'ready': True})
    while (body := read_packet(sys.stdin.buffer)) is not None:
        header, pixels = decode_frame(body)
        rgb = np.frombuffer(pixels, dtype=np.uint8).reshape(header['height'], header['width'], 3)
        with contextlib.redirect_stdout(sys.stderr):
            result = model.predict(rgb[:, :, ::-1].copy(), classes=[0, 2], conf=0.35,
                                   iou=0.45, imgsz=640, rect=False, device='cpu',
                                   max_det=100, verbose=False)[0]
        objects = []
        for box in result.boxes:
            cls = int(box.cls.item())
            if cls in (0, 2):
                objects.append({'class_id': cls, 'confidence': float(box.conf.item()),
                                'xyxy': box.xyxy[0].tolist()})
        send(output, {'frame_id': header['frame_id'], 'objects': objects})


if __name__ == '__main__':
    try:
        main()
    except (ValueError, EOFError, BrokenPipeError):
        sys.exit(2)
