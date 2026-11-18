import importlib.util
import io
import json
import struct
from pathlib import Path
import pytest

spec = importlib.util.spec_from_file_location('worker', Path(__file__).parents[1] / 'worker.py')
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


def body(header, pixels):
    encoded = json.dumps(header).encode()
    return struct.pack('>I', len(encoded)) + encoded + pixels


def test_rgb_payload_is_preserved():
    header, pixels = worker.decode_frame(body({'width': 1, 'height': 1, 'frame_id': 7}, b'\xff\x00\x00'))
    assert header['frame_id'] == 7
    assert pixels == b'\xff\x00\x00'


@pytest.mark.parametrize('packet', [b'', b'\x00\x00\x00\x00', body({'width': 1281, 'height': 1}, b''), body({'width': 1, 'height': 1}, b'\x00')])
def test_invalid_frame_rejected(packet):
    with pytest.raises(ValueError):
        worker.decode_frame(packet)


def test_packets_reject_oversize_and_truncation():
    for payload in (struct.pack('>I', worker.MAX_PACKET + 1), struct.pack('>I', 8) + b'a'):
        with pytest.raises(ValueError):
            worker.read_packet(io.BytesIO(payload))
    assert worker.read_packet(io.BytesIO()) is None


def test_response_packet_and_no_nan():
    output = io.BytesIO()
    worker.send(output, {'objects': []})
    assert json.loads(worker.read_packet(io.BytesIO(output.getvalue()))) == {'objects': []}
    with pytest.raises(ValueError):
        worker.send(output, {'confidence': float('nan')})
