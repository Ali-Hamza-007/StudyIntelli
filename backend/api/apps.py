import os
import socket
import threading
import time
from django.apps import AppConfig


class ApiConfig(AppConfig):
    name = 'api'

    def ready(self):
        # Start discovery beacon in the main runserver process
        if os.environ.get('RUN_MAIN') == 'true' or not os.environ.get('DJANGO_SETTINGS_MODULE'):
            self._start_udp_beacon()

    def _start_udp_beacon(self):
        def beacon_worker():
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.settimeout(1.0)
                try:
                    sock.bind(('0.0.0.0', 8888))
                except Exception:
                    pass

                beacon_bytes = b'STUDYINTELLI_BEACON:8000'
                pong_bytes = b'STUDYINTELLI_PONG:8000'
                last_beacon = 0

                while True:
                    # 1. Check for discovery ping
                    try:
                        data, addr = sock.recvfrom(1024)
                        if b'STUDYINTELLI' in data:
                            sock.sendto(pong_bytes, addr)
                    except (socket.timeout, OSError):
                        pass
                    except Exception:
                        pass

                    # 2. Broadcast beacon every 2 seconds
                    now = time.time()
                    if now - last_beacon >= 2.0:
                        try:
                            sock.sendto(beacon_bytes, ('255.255.255.255', 8888))
                        except Exception:
                            pass
                        last_beacon = now

            except Exception:
                pass

        t = threading.Thread(target=beacon_worker, daemon=True, name="UDP_Beacon_Thread")
        t.start()

