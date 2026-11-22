"""EcoFlow app API client. Credentials arrive over stdin, never argv.

Protocol references (independent implementation using Python standard library):
https://github.com/tolwi/hassio-ecoflow-cloud/blob/main/custom_components/ecoflow_cloud/api/private_api.py
https://github.com/LM1LC3N7/gladys-ecoflow/blob/main/src/ecoflow/privateClient.js
"""
import base64
import json
import socket
import ssl
import struct
import sys
import time
import urllib.error
import urllib.request
import uuid


class ClientError(Exception):
    def __init__(self, message, auth=False):
        super().__init__(message)
        self.auth = auth


def request(host, path, body=None, token=None):
    if host not in ('https://api-e.ecoflow.com', 'https://api-a.ecoflow.com',
                    'https://api.ecoflow.com'):
        raise ClientError('Недопустимый сервер EcoFlow.')
    headers = {'Content-Type': 'application/json', 'lang': 'en_US'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(host + path, headers=headers,
                                 data=json.dumps(body).encode() if body is not None else None)
    # Do not forward login credentials or bearer tokens across redirects.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=15) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        raise ClientError('EcoFlow HTTP %s. Проверь регион аккаунта.' % exc.code,
                          auth=exc.code in (401, 403)) from None
    if str(result.get('code')) != '0' and str(result.get('message', '')).lower() != 'success':
        # Show only the code; server error strings could echo request data.
        code = str(result.get('code', '?'))
        if not (code.isascii() and code.isdecimal() and len(code) <= 12):
            code = '?'
        raise ClientError('EcoFlow отклонил вход/запрос (код %s). Проверь регион, email и пароль.' % code,
                          auth=True)
    return result['data']


def login(config):
    data = request(config['Host'], '/auth/login', {
        'email': config['Email'],
        'password': base64.b64encode(config['Password'].encode()).decode(),
        'scene': 'IOT_APP', 'userType': 'ECOFLOW'})
    cert = request(config['Host'], '/iot-auth/app/certification', token=data['token'])
    return {'userId': str(data['user']['userId']), 'url': cert['url'],
            'port': int(cert['port']), 'username': cert['certificateAccount'],
            'password': cert['certificatePassword'], 'expires': time.time() + 1800}


def mqtt_string(value):
    data = value.encode('utf-8')
    if len(data) > 65535:
        raise ClientError('Слишком длинное поле MQTT.')
    return struct.pack('!H', len(data)) + data


def send_packet(stream, header, body):
    length = len(body)
    encoded = bytearray([header])
    while True:
        digit = length % 128
        length //= 128
        encoded.append(digit | (128 if length else 0))
        if not length:
            break
    stream.sendall(bytes(encoded) + body)


def read_exact(stream, count):
    data = bytearray()
    while len(data) < count:
        part = stream.recv(count - len(data))
        if not part:
            raise ClientError('EcoFlow закрыл соединение. Попробуй подключиться ещё раз.')
        data.extend(part)
    return bytes(data)


def read_packet(stream):
    header = read_exact(stream, 1)[0]
    length = 0
    for i in range(4):
        digit = read_exact(stream, 1)[0]
        length += (digit & 127) << (7 * i)
        if not digit & 128:
            break
    else:
        raise ClientError('Некорректный ответ MQTT.')
    if length > 2 * 1024 * 1024:
        raise ClientError('Ответ MQTT превышает допустимый размер.')
    return header, read_exact(stream, length)


def broker_address(session):
    raw = session['url']
    # EcoFlow may return a bare hostname or an mqtts:// URL.
    from urllib.parse import urlsplit
    parsed = urlsplit(raw if '://' in raw else 'mqtts://' + raw)
    hostname = parsed.hostname or ''
    if not hostname.endswith('.ecoflow.com'):
        raise ClientError('Сервер вернул неизвестный адрес MQTT.')
    return hostname, int(session['port'])


def read_quota(session, serial):
    host, port = broker_address(session)
    base = 'ANDROID_' + uuid.uuid4().hex.upper() + '_' + session['userId']
    # The private API login assigns ANDROID_<UUID>_<userId> as client_id.
    client_id = base
    topic = '/app/%s/%s/thing/property' % (session['userId'], serial)
    with socket.create_connection((host, port), timeout=12) as tcp:
        with ssl.create_default_context().wrap_socket(tcp, server_hostname=host) as stream:
            stream.settimeout(15)
            body = mqtt_string('MQTT') + bytes([4, 0xC2, 0, 45])
            body += mqtt_string(client_id) + mqtt_string(session['username']) + mqtt_string(session['password'])
            send_packet(stream, 0x10, body)
            head, ack = read_packet(stream)
            if head != 0x20 or len(ack) != 2 or ack[1] != 0:
                raise ClientError('Сервер EcoFlow отклонил MQTT-вход. Переподключись.', auth=True)
            send_packet(stream, 0x82, b'\x00\x01' + mqtt_string(topic + '/get_reply') + b'\x01')
            head, ack = read_packet(stream)
            if head != 0x90 or len(ack) != 3 or ack[:2] != b'\x00\x01' or ack[2] == 0x80:
                raise ClientError('Нет доступа к данным станции. Проверь SN и аккаунт.')
            message = json.dumps({'from': 'Android', 'id': int(time.time() * 1000),
                                  'version': '1.1', 'moduleType': 0,
                                  'operateType': 'latestQuotas', 'params': {}}, separators=(',', ':'))
            send_packet(stream, 0x32, mqtt_string(topic + '/get') + b'\x00\x02' + message.encode())
            deadline = time.monotonic() + 18
            while time.monotonic() < deadline:
                stream.settimeout(max(0.1, deadline - time.monotonic()))
                head, body = read_packet(stream)
                if head >> 4 != 3:
                    continue
                if len(body) < 2:
                    raise ClientError('Неполный ответ MQTT.')
                size = struct.unpack('!H', body[:2])[0]
                if len(body) < 2 + size:
                    raise ClientError('Неполный ответ MQTT.')
                received_topic = body[2:2 + size].decode()
                offset = size + 2
                qos = (head >> 1) & 3
                if qos:
                    if len(body) < offset + 2 or qos != 1:
                        raise ClientError('Неподдерживаемый ответ MQTT.')
                    packet_id = body[offset:offset + 2]
                    offset += 2
                    send_packet(stream, 0x40, packet_id)
                # Retained messages may be outdated; await a fresh reply.
                if head & 1 or received_topic != topic + '/get_reply':
                    continue
                reply = json.loads(body[offset:])
                if reply.get('operateType') != 'latestQuotas':
                    continue
                quota = reply.get('data', {}).get('quotaMap')
                if not isinstance(quota, dict) or not quota:
                    raise ClientError('Станция ответила без показателей. Проверь, что она в сети.')
                send_packet(stream, 0xE0, b'')
                return quota
            raise ClientError('Станция не ответила. Проверь SN, Wi-Fi и аккаунт.')


def publish_setting(session, serial, operation, params):
    """Publish one command; a broker acknowledgement is not device confirmation."""
    host, port = broker_address(session)
    client_id = 'ANDROID_' + uuid.uuid4().hex.upper() + '_' + session['userId']
    topic = '/app/%s/%s/thing/property/set' % (session['userId'], serial)
    with socket.create_connection((host, port), timeout=12) as tcp:
        with ssl.create_default_context().wrap_socket(tcp, server_hostname=host) as stream:
            stream.settimeout(15)
            body = mqtt_string('MQTT') + bytes([4, 0xC2, 0, 45])
            body += mqtt_string(client_id) + mqtt_string(session['username']) + mqtt_string(session['password'])
            send_packet(stream, 0x10, body)
            head, ack = read_packet(stream)
            if head != 0x20 or len(ack) != 2 or ack[1] != 0:
                raise ClientError('Сервер EcoFlow отклонил MQTT-вход. Переподключись.', auth=True)
            message = json.dumps({'from': 'Android', 'id': str(int(time.time() * 1000)),
                                  'version': '1.0', 'moduleType': 5, 'operateType': operation,
                                  'params': params}, separators=(',', ':'))
            try:
                send_packet(stream, 0x32, mqtt_string(topic) + b'\x00\x02' + message.encode())
                head, ack = read_packet(stream)
                if head != 0x40 or ack != b'\x00\x02':
                    raise ClientError('Нет подтверждения отправки. Проверь настройку в приложении EcoFlow.')
            except (OSError, TimeoutError, ClientError):
                raise ClientError('Результат неизвестен. Проверь настройку в приложении EcoFlow.') from None
            # No disconnect is needed for this short-lived clean session.


def set_ac_charging_power(session, serial, watts):
    if type(watts) is not int or not 50 <= watts <= 870:
        raise ClientError('Укажи целое значение от 50 до 870 Вт.')
    publish_setting(session, serial, 'acChgCfg', {'chgWatts': watts, 'chgPauseFlag': 255})


def set_xboost(session, serial, enabled):
    if type(enabled) is not bool:
        raise ClientError('Некорректное состояние X-Boost.')
    publish_setting(session, serial, 'acOutCfg',
                    {'enabled': 255, 'out_voltage': -1, 'out_freq': 255, 'xboost': int(enabled)})


def confirmed_xboost(quota):
    value = quota.get('mppt.cfgAcXboost')
    return value if type(value) is int and value in (0, 1) else None


def confirmed_charge_power(quota):
    value = quota.get('mppt.cfgChgWatts')
    return value if type(value) is int and 50 <= value <= 870 else None


def change_ac_charging_power(session, serial, watts):
    set_ac_charging_power(session, serial, watts)
    # A fresh quota, not MQTT delivery, is the evidence that the station applied it.
    for attempt in range(2):
        time.sleep(2 if attempt == 0 else 3)
        try:
            quota = read_quota(session, serial)
        except (ClientError, socket.timeout, TimeoutError):
            continue
        if confirmed_charge_power(quota) == watts:
            return {'Ok': True, 'Data': quota, 'Session': session}
    return {'Ok': False, 'Session': session,
            'Error': 'Команда отправлена, но станция не подтвердила значение. Проверь приложение EcoFlow.'}


def change_xboost(session, serial, enabled):
    set_xboost(session, serial, enabled)
    for attempt in range(2):
        time.sleep(2 if attempt == 0 else 3)
        try:
            quota = read_quota(session, serial)
        except (ClientError, socket.timeout, TimeoutError):
            continue
        if confirmed_xboost(quota) == int(enabled):
            return {'Ok': True, 'Data': quota, 'Session': session}
    return {'Ok': False, 'Session': session,
            'Error': 'Команда отправлена, но станция не подтвердила X-Boost. Проверь приложение EcoFlow.'}


def run(config):
    session = config.get('Session')
    if not session or session.get('expires', 0) < time.time():
        session = login(config)
    try:
        if config.get('Operation') == 'SetAcChargingPower':
            return change_ac_charging_power(session, config['Serial'], config.get('Watts'))
        if config.get('Operation') == 'SetXBoost':
            return change_xboost(session, config['Serial'], config.get('Enabled'))
        return {'Ok': True, 'Data': read_quota(session, config['Serial']), 'Session': session}
    except ClientError as exc:
        if exc.auth:
            raise
        return {'Ok': False, 'Error': str(exc), 'Session': session}
    except (socket.timeout, TimeoutError):
        return {'Ok': False, 'Error': 'Нет ответа станции. Проверь SN и Wi-Fi; повтор через 30 секунд.', 'Session': session}


def main():
    try:
        # Windows PowerShell/.NET Framework can append a UTF-8 BOM when closing
        # its stdin StreamWriter after direct writes to BaseStream.
        raw = sys.stdin.buffer.read()
        config = json.loads(raw.decode('utf-8-sig').strip('\ufeff \t\r\n'))
        result = run(config)
    except ClientError as exc:
        result = {'Ok': False, 'Error': str(exc), 'AuthFailed': exc.auth}
    except (urllib.error.URLError, OSError):
        result = {'Ok': False, 'Error': 'Нет соединения с EcoFlow. Проверь интернет и регион.'}
    except Exception as exc:
        import traceback
        frames = traceback.extract_tb(exc.__traceback__)
        diagnostic = {'type': type(exc).__name__,
                      'location': [{'function': f.name, 'line': f.lineno} for f in frames]}
        result = {'Ok': False, 'Error': 'Неожиданный формат ответа EcoFlow. Требуется проверка подключения.',
                  'Diagnostic': diagnostic}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == '__main__':
    main()
