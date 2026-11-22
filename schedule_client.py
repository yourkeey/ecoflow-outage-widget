"""Public CEK channel reader. No Telegram account, credentials or third-party deps."""
import argparse
from datetime import datetime, timedelta
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import urllib.request

CHANNEL = 'https://t.me/s/cek_info'
MONTHS = {name: index + 1 for index, name in enumerate(
    ('січня', 'лютого', 'березня', 'квітня', 'травня', 'червня',
     'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня'))}
GROUP = re.compile(r'(?:черг[аиу]|підчерг[аиу])\s*(\d)\s*[.,]\s*(\d)\b', re.I)
INTERVAL = re.compile(r'(?<!\d)(\d{1,2})[:.](\d{2})\s*[-–—−]\s*(\d{1,2})[:.](\d{2})(?!\d)')
LIST_UPDATE = re.compile(
    r'з\s+(\d{1,2}):(\d{2})\s+до\s+(\d{1,2}):(\d{2})\s+'
    r'застосовуються\s+відк?лючення\s+черг\s*:\s*'
    r'(\d\s*[.,]\s*\d(?:\s*,\s*\d\s*[.,]\s*\d)*)', re.I)


class ChannelParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.posts = []
        self.current = None
        self.depth = 0
        self.text_depth = None
        self.parts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = attrs.get('class', '').split()
        if tag == 'div' and re.fullmatch(r'cek_info/\d+', attrs.get('data-post', '')):
            self.current = {'id': int(attrs['data-post'].split('/')[1]),
                            'url': 'https://t.me/' + attrs['data-post'],
                            'published': None, 'photo': False, 'text': ''}
            self.depth = 0
            self.parts = []
        if self.current is None:
            return
        if tag == 'div':
            self.depth += 1
        if 'tgme_widget_message_text' in classes:
            self.text_depth = self.depth
        if tag == 'br' and self.text_depth is not None:
            self.parts.append('\n')
        if tag == 'time' and attrs.get('datetime'):
            self.current['published'] = attrs['datetime']
        if 'tgme_widget_message_photo_wrap' in classes:
            self.current['photo'] = True

    def handle_endtag(self, tag):
        if self.current is None or tag != 'div':
            return
        if self.text_depth == self.depth:
            self.text_depth = None
        self.depth -= 1
        if self.depth == 0:
            self.current['text'] = ''.join(self.parts).strip()
            self.posts.append(self.current)
            self.current = None
            self.text_depth = None

    def handle_data(self, data):
        if self.current is not None and self.text_depth is not None:
            self.parts.append(data)


def read_posts(html):
    parser = ChannelParser()
    parser.feed(html)
    return parser.posts


def schedule_date(text, published):
    match = re.search(r'\b(\d{1,2})\s+(' + '|'.join(MONTHS) + r')(?:\s+(20\d{2}))?\b', text, re.I)
    if match:
        year = int(match[3]) if match[3] else published.year
        try:
            result = published.date().replace(year=year, month=MONTHS[match[2].lower()], day=int(match[1]))
            if not match[3]:
                if (result - published.date()).days > 180:
                    result = result.replace(year=year - 1)
                elif (published.date() - result).days > 180:
                    result = result.replace(year=year + 1)
            return result
        except ValueError:
            return None
    match = re.search(r'\b(\d{2})[./](\d{2})[./](20\d{2})\b', text)
    if match:
        try:
            return published.date().replace(year=int(match[3]), month=int(match[2]), day=int(match[1]))
        except ValueError:
            return None
    if re.search(r'\bзавтра\b', text, re.I):
        return published.date() + timedelta(days=1)
    if re.search(r'\bсьогодні\b', text, re.I):
        return published.date()
    return None


def minutes(hour, minute):
    hour, minute = int(hour), int(minute)
    if hour > 24 or minute > 59 or (hour == 24 and minute):
        raise ValueError('Invalid clock time')
    return hour * 60 + minute


def merge(intervals):
    result = []
    for start, end in sorted(intervals):
        if start >= end:
            continue
        if result and start <= result[-1][1]:
            result[-1][1] = max(end, result[-1][1])
        else:
            result.append([start, end])
    return result


def extract_schedule(post, now, queue='2.2'):
    text = post['text']
    if not post.get('published') or not re.search(r'ГПВ|графік|відключ|знеструм', text, re.I):
        return None
    # Some updates specify one common interval followed by a list of queues.
    listed = LIST_UPDATE.search(text)
    if listed and re.search(r'змін|уточнен|коригув', text[:listed.start()], re.I):
        published = datetime.fromisoformat(post['published']).astimezone(now.tzinfo)
        date = schedule_date(text[:listed.start()], published)
        try:
            start, end = minutes(listed[1], listed[2]), minutes(listed[3], listed[4])
        except ValueError:
            return None
        if date is None or start >= end:
            return None
        queues = [re.sub(r'\s+', '', q).replace(',', '.')
                  for q in re.findall(r'\d\s*[.,]\s*\d', listed[5])]
        return {'date': date.isoformat(), 'intervals': [[start, end]],
                'mentioned': queue in queues, 'ambiguous': False, 'is_update': True,
                'effective': start, 'effective_end': end,
                'source': post['url'], 'published': post['published'], 'postId': post['id']}
    # Queue headings stand on their own line. An inline mention in an
    # address-specific notice must not replace the regional schedule.
    groups = []
    for group in GROUP.finditer(text):
        line_start = text.rfind('\n', 0, group.start()) + 1
        line_end = text.find('\n', group.end())
        suffix = text[group.end():line_end if line_end != -1 else len(text)].strip()
        if re.search(r'\w', text[line_start:group.start()]):
            continue
        if suffix and not INTERVAL.search(suffix) and not re.search(r'не\s+(?:застосов|відключ)|без\s+відключ|скасован', suffix, re.I) and re.search(r'\w', suffix):
            continue
        groups.append(group)
    if not groups:
        return None  # Address repairs and nationwide notices are not queue schedules.
    published = datetime.fromisoformat(post['published']).astimezone(now.tzinfo)
    # Only the header defines the schedule date; other groups may contain notes.
    header = text[:groups[0].start()]
    date = schedule_date(header, published)
    if date is None:
        return None
    intervals = []
    mentioned = False
    ambiguous = False
    for index, group in enumerate(groups):
        if group[1] + '.' + group[2] != queue:
            continue
        mentioned = True
        section = text[group.end():groups[index + 1].start() if index + 1 < len(groups) else len(text)]
        found = list(INTERVAL.finditer(section))
        if not found and not re.search(r'не\s+(?:застосов|відключ)|без\s+відключ|скасован', section, re.I):
            ambiguous = True
        for item in found:
            try:
                start, end = minutes(item[1], item[2]), minutes(item[3], item[4])
                if start == end:
                    ambiguous = True
                elif end < start:
                    intervals.extend([[start, 1440], [0, end]])
                else:
                    intervals.append([start, end])
            except ValueError:
                ambiguous = True
    effective = re.search(r'з(?:і)?\s+(\d{1,2}):(\d{2})', header, re.I)
    effective_minute = minutes(effective[1], effective[2]) if effective else None
    return {'date': date.isoformat(), 'intervals': merge(intervals),
            'mentioned': mentioned, 'ambiguous': ambiguous,
            'is_update': bool(re.search(r'змін|уточнен|коригув', header, re.I)),
            'effective': effective_minute,
            'source': post['url'], 'published': post['published'], 'postId': post['id']}


def build_schedule(posts, now, queue='2.2'):
    days = {}
    unparsed = []
    for post in sorted(posts, key=lambda item: item['id']):
        item = extract_schedule(post, now, queue)
        if not item:
            if post.get('photo') or (re.search(r'ГПВ|графік|відключ', post['text'], re.I)
                                     and not re.search(r'ремонт|планові роботи', post['text'], re.I)):
                unparsed.append({'source': post['url'], 'postId': post['id']})
            continue
        previous = days.get(item['date'])
        # A partial update omitting this queue doesn't cancel its previous slots.
        if not item['mentioned'] and item['is_update']:
            continue
        if item['mentioned'] and item['effective'] is not None and previous:
            before = [[start, min(end, item['effective'])] for start, end in previous['intervals']
                      if start < item['effective']]
            after = [[max(start, item['effective']), end] for start, end in item['intervals']
                     if end > item['effective']]
            if item.get('effective_end') is not None:
                after += [[max(start, item['effective_end']), end]
                          for start, end in previous['intervals'] if end > item['effective_end']]
            item['intervals'] = merge(before + after)
            item['ambiguous'] = item['ambiguous'] or previous['ambiguous']
        elif item.get('effective_end') is not None:
            item['ambiguous'] = True  # The update alone does not describe the whole day.
        days[item['date']] = item
    ordered = sorted(days.values(), key=lambda item: item['date'], reverse=True)
    return {'Ok': True, 'queue': queue, 'today': now.date().isoformat(),
            'checkedAt': now.isoformat(), 'cached': False, 'days': ordered,
            'unparsed': unparsed,
            'latestPost': max(posts, key=lambda p: p['id'])['url'] if posts else CHANNEL}


def fetch_posts(now):
    posts = {}
    url = CHANNEL
    for _ in range(3):
        request = urllib.request.Request(url, headers={'User-Agent': 'EcoFlowWidget/1.0 (public schedule reader)'})
        with urllib.request.urlopen(request, timeout=15) as response:
            html = response.read(4 * 1024 * 1024).decode('utf-8')
        page = read_posts(html)
        if not page:
            raise ValueError('No public posts')
        for post in page:
            posts[post['id']] = post
        dates = [datetime.fromisoformat(p['published']).astimezone(now.tzinfo).date()
                 for p in page if p.get('published')]
        if dates and min(dates) < now.date() - timedelta(days=1):
            break
        url = CHANNEL + '?before=' + str(min(p['id'] for p in page))
    return list(posts.values())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--now')
    parser.add_argument('--html', type=Path)
    args = parser.parse_args()
    now = datetime.fromisoformat(args.now) if args.now else datetime.now().astimezone()
    cache = Path(__file__).with_name('schedule-cache.json')
    try:
        posts = read_posts(args.html.read_text(encoding='utf-8-sig')) if args.html else fetch_posts(now)
        result = build_schedule(posts, now)
        if not args.html:
            temporary = cache.with_suffix('.tmp')
            temporary.write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
            temporary.replace(cache)
    except Exception:
        try:
            result = json.loads(cache.read_text(encoding='utf-8'))
            result.update(cached=True, today=now.date().isoformat(), error='Нет связи с Telegram. Показана сохранённая публикация.')
        except Exception:
            result = {'Ok': False, 'error': 'Не удалось прочитать канал ЦЕК. Попробуй обновить позже.'}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == '__main__':
    main()
