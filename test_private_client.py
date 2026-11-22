import io
import json
import socket
import sys
import unittest
from unittest.mock import patch

import private_client as client


class FakeStream:
    def __init__(self, incoming=b''):
        self.incoming = io.BytesIO(incoming)
        self.sent = bytearray()

    def recv(self, count):
        return self.incoming.read(min(count, 3))  # fragmented TCP packets

    def sendall(self, data):
        self.sent.extend(data)

    def settimeout(self, timeout):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass


def packet(header, body):
    stream = FakeStream()
    client.send_packet(stream, header, body)
    return bytes(stream.sent)


class PrivateClientTests(unittest.TestCase):
    session = {'userId': '1234', 'url': 'mqtt-e.ecoflow.com', 'port': 8883,
               'username': 'mqtt-user', 'password': 'mqtt-secret', 'expires': 9999999999}

    def test_fragmented_packets_and_multibyte_lengths(self):
        payload = b'x' * 14000
        stream = FakeStream(packet(0x30, payload))
        self.assertEqual(client.read_packet(stream), (0x30, payload))

    def test_windows_stdin_bom_and_cyrillic_credentials(self):
        config = {'Email': 'test@example.com', 'Password': 'пароль'}
        raw = b'\xef\xbb\xbf' + json.dumps(config, ensure_ascii=False).encode() + b'\n\xef\xbb\xbf'
        stdin = io.TextIOWrapper(io.BytesIO(raw), encoding='utf-8')
        output = io.StringIO()
        with patch.object(sys, 'stdin', stdin), patch.object(sys, 'stdout', output), \
                patch.object(client, 'run', return_value={'Ok': True}) as run:
            client.main()
        run.assert_called_once_with(config)
        self.assertTrue(json.loads(output.getvalue())['Ok'])

    def test_rejects_invalid_length_and_closed_stream(self):
        for raw in (b'\x30\xff\xff\xff\xff', b'\x30\x05xx'):
            with self.assertRaises(client.ClientError):
                client.read_packet(FakeStream(raw))

    def test_quota_exchange_ignores_retained_and_acknowledges_qos1(self):
        topic = '/app/1234/R62TEST/thing/property'
        quota = {'pd.soc': 81, 'pd.wattsInSum': 0, 'pd.wattsOutSum': 135}
        reply = json.dumps({'operateType': 'latestQuotas', 'data': {'quotaMap': quota}}).encode()
        body = client.mqtt_string(topic + '/get_reply') + b'\x00\x09' + reply
        incoming = packet(0x20, b'\x00\x00') + packet(0x90, b'\x00\x01\x01')
        incoming += packet(0x33, body) + packet(0x40, b'\x00\x02') + packet(0x32, body)
        stream = FakeStream(incoming)
        with patch.object(client.socket, 'create_connection', return_value=FakeStream()), \
                patch.object(client.ssl, 'create_default_context') as ctx:
            ctx.return_value.wrap_socket.return_value = stream
            self.assertEqual(client.read_quota(self.session, 'R62TEST'), quota)
            ctx.return_value.wrap_socket.assert_called_once()
        sent = FakeStream(bytes(stream.sent))
        packets = []
        while sent.incoming.tell() < len(stream.sent):
            packets.append(client.read_packet(sent))
        self.assertEqual([head for head, _ in packets], [0x10, 0x82, 0x32, 0x40, 0x40, 0xE0])
        publish = packets[2][1]
        self.assertIn(b'latestQuotas', publish)
        self.assertNotIn(b'/set', bytes(stream.sent))

    def test_charge_command_payload_and_limits(self):
        incoming = packet(0x20, b'\x00\x00') + packet(0x40, b'\x00\x02')
        stream = FakeStream(incoming)
        with patch.object(client.socket, 'create_connection', return_value=FakeStream()) as connect, \
                patch.object(client.ssl, 'create_default_context') as ctx:
            ctx.return_value.wrap_socket.return_value = stream
            for invalid in (49, 871, 50.5, True, '500'):
                with self.assertRaises(client.ClientError):
                    client.set_ac_charging_power(self.session, 'R62TEST', invalid)
            connect.assert_not_called()
            client.set_ac_charging_power(self.session, 'R62TEST', 500)
        sent = FakeStream(bytes(stream.sent))
        client.read_packet(sent)
        header, body = client.read_packet(sent)
        self.assertEqual(header, 0x32)
        topic_size = int.from_bytes(body[:2], 'big')
        self.assertEqual(body[2:2 + topic_size], b'/app/1234/R62TEST/thing/property/set')
        payload = json.loads(body[4 + topic_size:])
        self.assertEqual(payload['operateType'], 'acChgCfg')
        self.assertEqual(payload['moduleType'], 5)
        self.assertEqual(payload['params'], {'chgWatts': 500, 'chgPauseFlag': 255})

    def test_command_requires_fresh_device_value(self):
        with patch.object(client, 'set_ac_charging_power') as send, \
                patch.object(client, 'read_quota', side_effect=[{'mppt.cfgChgWatts': 100},
                                                                 {'mppt.cfgChgWatts': 500}]), \
                patch.object(client.time, 'sleep'):
            result = client.change_ac_charging_power(self.session, 'R62TEST', 500)
        self.assertTrue(result['Ok'])
        send.assert_called_once_with(self.session, 'R62TEST', 500)
        with patch.object(client, 'set_ac_charging_power'), \
                patch.object(client, 'read_quota', return_value={'mppt.cfgChgWatts': 100}), \
                patch.object(client.time, 'sleep'):
            result = client.change_ac_charging_power(self.session, 'R62TEST', 500)
        self.assertFalse(result['Ok'])
        self.assertIn('не подтвердила', result['Error'])

    def test_lost_broker_ack_is_reported_as_unknown(self):
        stream = FakeStream(packet(0x20, b'\x00\x00'))
        with patch.object(client.socket, 'create_connection', return_value=FakeStream()), \
                patch.object(client.ssl, 'create_default_context') as ctx:
            ctx.return_value.wrap_socket.return_value = stream
            with self.assertRaisesRegex(client.ClientError, 'Результат неизвестен'):
                client.set_ac_charging_power(self.session, 'R62TEST', 500)

    def test_xboost_payload_preserves_other_ac_settings(self):
        with patch.object(client, 'publish_setting') as publish:
            client.set_xboost(self.session, 'R62TEST', True)
            publish.assert_called_once_with(self.session, 'R62TEST', 'acOutCfg',
                                           {'enabled': 255, 'out_voltage': -1,
                                            'out_freq': 255, 'xboost': 1})
            for invalid in (0, 1, 'true', None):
                with self.assertRaises(client.ClientError):
                    client.set_xboost(self.session, 'R62TEST', invalid)
            self.assertEqual(publish.call_count, 1)

    def test_xboost_confirmed_only_by_reported_setting(self):
        with patch.object(client, 'set_xboost') as send, \
                patch.object(client, 'read_quota', side_effect=[{'mppt.cfgAcXboost': 0},
                                                                 {'mppt.cfgAcXboost': 1}]), \
                patch.object(client.time, 'sleep'):
            result = client.change_xboost(self.session, 'R62TEST', True)
        self.assertTrue(result['Ok'])
        send.assert_called_once_with(self.session, 'R62TEST', True)
        with patch.object(client, 'set_xboost'), \
                patch.object(client, 'read_quota', return_value={}), \
                patch.object(client.time, 'sleep'):
            result = client.change_xboost(self.session, 'R62TEST', False)
        self.assertFalse(result['Ok'])
        self.assertIn('не подтвердила', result['Error'])

    def test_mqtt_auth_rejection_stops_login_retry(self):
        stream = FakeStream(packet(0x20, b'\x00\x05'))
        with patch.object(client.socket, 'create_connection', return_value=FakeStream()), \
                patch.object(client.ssl, 'create_default_context') as ctx:
            ctx.return_value.wrap_socket.return_value = stream
            with self.assertRaises(client.ClientError) as error:
                client.read_quota(self.session, 'R62TEST')
            self.assertTrue(error.exception.auth)

    def test_cached_session_and_offline_result(self):
        config = {'Session': self.session, 'Serial': 'R62TEST'}
        with patch.object(client, 'login') as login, \
                patch.object(client, 'read_quota', side_effect=socket.timeout):
            result = client.run(config)
        login.assert_not_called()
        self.assertFalse(result['Ok'])
        self.assertEqual(result['Session'], self.session)

    def test_does_not_send_credentials_to_unknown_broker(self):
        for host in ('attacker.example', 'mqtt-e.ecoflow.com.attacker.example'):
            with self.assertRaises(client.ClientError):
                client.broker_address(dict(self.session, url=host))

    def test_login_payload_and_certificate_request(self):
        config = {'Host': 'https://api-e.ecoflow.com', 'Email': 'test@example.com', 'Password': 'пароль'}
        with patch.object(client, 'request', side_effect=[
                {'token': 'private-token', 'user': {'userId': 1234}},
                {'url': 'mqtt-e.ecoflow.com', 'port': '8883',
                 'certificateAccount': 'user', 'certificatePassword': 'secret'}]) as req:
            session = client.login(config)
        self.assertEqual(session['userId'], '1234')
        self.assertEqual(req.call_args_list[0].args[2]['scene'], 'IOT_APP')
        self.assertEqual(req.call_args_list[1].kwargs, {'token': 'private-token'})
        self.assertNotEqual(req.call_args_list[0].args[2]['password'], config['Password'])


if __name__ == '__main__':
    unittest.main()
