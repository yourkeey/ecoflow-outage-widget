from datetime import datetime
import unittest

import schedule_client as client

NOW = datetime.fromisoformat('2026-10-18T00:30:00+03:00')


def post(number, text, published='2026-10-17T15:00:00+00:00'):
    return {'id': number, 'text': text, 'published': published,
            'url': 'https://t.me/cek_info/' + str(number), 'photo': False}


class ScheduleTests(unittest.TestCase):
    def test_group_selection_and_latest_correction(self):
        posts = [post(1, 'ГПВ на 18 ЖОВТНЯ\nЧерга 2.1\n01:00-02:00\nЧерга 2.2\n06:00-09:30\n18:00-20:00\nЧерга 3.1\n10:00-12:00'),
                 post(2, 'Зміни ГПВ на 18 ЖОВТНЯ\nЧерга 2.2\n07:00–10:00')]
        day = client.build_schedule(posts, NOW)['days'][0]
        self.assertEqual(day['intervals'], [[420, 600]])
        self.assertEqual(day['source'], 'https://t.me/cek_info/2')

    def test_partial_update_keeps_past_intervals(self):
        posts = [post(1, 'ГПВ на 18 ЖОВТНЯ\nЧерга 2.2\n06:00-08:00\n17:00-21:00'),
                 post(2, 'Зміни у ГПВ з 17:00 на 18 ЖОВТНЯ\nЧерга 2.2\n18:00-20:30')]
        self.assertEqual(client.build_schedule(posts, NOW)['days'][0]['intervals'], [[360, 480], [1080, 1230]])

    def test_update_to_other_group_does_not_cancel_our_group(self):
        posts = [post(1, 'ГПВ на 18 ЖОВТНЯ\nЧерга 2.2\n06:00-08:00'),
                 post(2, 'Зміни ГПВ на 18 ЖОВТНЯ\nЧерга 3.1\n12:00-14:00')]
        self.assertEqual(client.build_schedule(posts, NOW)['days'][0]['intervals'], [[360, 480]])

    def test_yesterday_never_becomes_today(self):
        data = client.build_schedule([post(1, 'ГПВ на 17 ЖОВТНЯ\nЧерга 2.2\n17:00-20:30')], NOW)
        self.assertEqual(data['days'][0]['date'], '2026-10-17')
        self.assertEqual(data['today'], '2026-10-18')

    def test_new_year_and_relative_date_from_publication(self):
        stamp = datetime.fromisoformat('2026-12-31T20:00:00+02:00')
        self.assertEqual(client.schedule_date('на 1 СІЧНЯ', stamp).isoformat(), '2027-01-01')
        self.assertEqual(client.schedule_date('завтра', stamp).isoformat(), '2027-01-01')

    def test_photo_and_repairs_are_not_invented_schedules(self):
        posts = [post(1, 'Ремонт 18 ЖОВТНЯ з 08:00-18:00 за адресою вул. Черга 2.2'),
                 dict(post(2, ''), photo=True)]
        data = client.build_schedule(posts, NOW)
        self.assertFalse(data['days'])
        self.assertEqual(data['unparsed'][0]['postId'], 2)

    def test_malformed_times_are_flagged(self):
        data = client.build_schedule([post(1, 'ГПВ на 18 ЖОВТНЯ\nЧерга 2.2\n28:00-29:00')], NOW)
        self.assertTrue(data['days'][0]['ambiguous'])
        self.assertFalse(data['days'][0]['intervals'])

    def test_html_extracts_only_message_text_not_footer(self):
        html = '<div class="tgme_widget_message" data-post="cek_info/12"><div class="tgme_widget_message_text">ГПВ на <b>18 ЖОВТНЯ</b><br/>Черга 2.2<br/>17:00-20:30</div><div>123 views<time datetime="2026-10-17T18:00:00+00:00">18:00</time></div></div>'
        posts = client.read_posts(html)
        self.assertEqual(len(posts), 1)
        self.assertNotIn('views', posts[0]['text'])
        self.assertEqual(client.build_schedule(posts, NOW)['days'][0]['intervals'], [[1020, 1230]])


if __name__ == '__main__':
    unittest.main()
