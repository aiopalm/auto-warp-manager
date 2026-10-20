'use strict';
'require view';
'require rpc';
'require ui';

var rpcStatus = rpc.declare({ object: 'luci.warp-autocheck', method: 'status' });
var rpcCheck = rpc.declare({ object: 'luci.warp-autocheck', method: 'check' });
var rpcRegen = rpc.declare({ object: 'luci.warp-autocheck', method: 'regen' });
var rpcLog = rpc.declare({ object: 'luci.warp-autocheck', method: 'log' });
var rpcGetSettings = rpc.declare({ object: 'luci.warp-autocheck', method: 'get_settings' });
var rpcSetSettings = rpc.declare({ object: 'luci.warp-autocheck', method: 'set_settings', params: ['enabled', 'interval', 'interface', 'retries'] });

var pollTimer = null;
var STYLES_ID = 'wac-styles';

var CSS = [
	'.wac-wrap { max-width: 860px; }',
	'.wac-card { background: rgba(127,127,127,.08); border: 1px solid rgba(127,127,127,.25); border-radius: 6px; padding: 14px 18px; margin-bottom: 14px; }',
	'.wac-card h3 { margin: 0 0 10px 0; font-size: 1.05rem; }',
	'.wac-row { display: flex; align-items: baseline; gap: 12px; padding: 4px 0; border-bottom: 1px solid rgba(127,127,127,.18); }',
	'.wac-row:last-child { border-bottom: 0 }',
	'.wac-key { width: 220px; min-width: 160px; opacity: .65; flex-shrink: 0 }',
	'.wac-val { word-break: break-word; overflow-wrap: anywhere }',
	'.wac-badge { display: inline-block; padding: 1px 9px; border-radius: 10px; font-size: 12px; color: #fff; background: #888; }',
	'.wac-badge.wac-ok { background: #2e9e44 }',
	'.wac-badge.wac-warn { background: #d09a2e }',
	'.wac-badge.wac-bad { background: #c9302c }',
	'.wac-badge.wac-mute { background: #7f8c9b }',
	'.wac-alert { border-left: 4px solid #c9302c; padding: 10px 14px; border-radius: 4px; background: rgba(201,48,44,.14); }',
	'.wac-actions { display: flex; gap: 10px; flex-wrap: wrap; align-items: center }',
	'.wac-log { max-height: 300px; overflow: auto; font-size: 12px; white-space: pre-wrap; word-break: break-all; background: rgba(127,127,127,.12); padding: 10px; border-radius: 4px; margin-top: 8px; }',
	'.wac-input { padding: 3px 8px; background: rgba(127,127,127,.1); border: 1px solid rgba(127,127,127,.3); border-radius: 4px; color: inherit }',
	'.wac-hint { font-size: 12px; opacity: .6; margin-top: 2px }',
	'.wac-busy { display: inline-block; padding: 1px 9px; border-radius: 10px; font-size: 12px; color: #fff; background: #356ac3; }'
].join('\n');

function ensureStyles() {
	if (document.getElementById(STYLES_ID)) return;
	var s = document.createElement('style');
	s.id = STYLES_ID;
	s.textContent = CSS;
	document.head.appendChild(s);
}

function fmtTime(ts) {
	if (!ts || ts === 0) return '—';
	var d = new Date(ts * 1000);
	return d.toLocaleString();
}

function resultBadge(res) {
	var map = {
		ok:           ['wac-ok',   'работает'],
		'replaced':   ['wac-ok',   'заменён и работает'],
		'no-link':    ['wac-bad',  'нет связи'],
		torn:         ['wac-warn', 'обрывается (DPI)'],
		'ru-colo':    ['wac-warn', 'российский узел'],
		'no-iface':   ['wac-bad',  'интерфейс не найден'],
		'manual-off': ['wac-mute', 'выключен вручную'],
		'wan-down':   ['wac-mute', 'сеть недоступна'],
		'no-conf':    ['wac-bad',  'конфиг не найден'],
		'not-helped': ['wac-warn', 'замена не помогла'],
		'regen-failed': ['wac-bad', 'регенерация не удалась'],
		'rolled-back':  ['wac-warn', 'заменён и откачен'],
		none:         ['wac-mute', 'ещё не проверялся']
	};
	var m = map[res] || ['wac-mute', res || '—'];
	return E('span', { 'class': 'wac-badge ' + m[0] }, m[1]);
}

function row(key, val) {
	var valChildren = Array.prototype.slice.call(arguments, 1);
	return E('div', { 'class': 'wac-row' }, [
		E('div', { 'class': 'wac-key' }, key),
		E('div', { 'class': 'wac-val' }, valChildren)
	]);
}

return view.extend({
	_statusCard: null,
	_actionsCard: null,
	_settingsCard: null,
	_logCard: null,
	_wrap: null,

	load: function () {
		return Promise.all([rpcStatus(), rpcGetSettings()]);
	},

	render: function (data) {
		ensureStyles();
		var status = data[0] || {};
		var settings = data[1] || {};
		var self = this;

		var wrap = E('div', { 'class': 'wac-wrap' });
		this._wrap = wrap;

		if (!status.conf_exists) {
			wrap.appendChild(E('div', { 'class': 'wac-card' }, [
				E('h3', {}, 'WARP AutoCheck'),
				E('div', { 'class': 'wac-alert' },
					'WARP-конфиг не найден (/root/WARP.conf). Сгенерируйте WARP-конфиг в Zapret Manager (раздел AmneziaWG) и импортируйте его как интерфейс.'
				)
			]));
			return wrap;
		}

		this._statusCard = this.renderStatus(status);
		this._actionsCard = this.renderActions(status);
		this._settingsCard = this.renderSettings(settings);
		this._logCard = this.renderLog();

		wrap.appendChild(this._statusCard);
		wrap.appendChild(this._actionsCard);
		wrap.appendChild(this._settingsCard);
		wrap.appendChild(this._logCard);

		this.startPolling(status.running);
		return wrap;
	},

	/* замена карточки на живую, без перезагрузки страницы */
	replaceCard: function (cardRef, newCard) {
		var old = this[cardRef];
		if (old && old.parentNode) {
			old.parentNode.replaceChild(newCard, old);
		}
		this[cardRef] = newCard;
	},

	liveUpdate: function (s) {
		if (!this._wrap || !s) return;
		this.replaceCard('_statusCard', this.renderStatus(s));
		this.replaceCard('_actionsCard', this.renderActions(s));
	},

	refreshAll: function () {
		var self = this;
		return Promise.all([rpcStatus(), rpcGetSettings()]).then(function (data) {
			var s = data[0] || {}, st = data[1] || {};
			self.liveUpdate(s);
			self.updateSettingsCard(st);
			self.refreshLog();
			return s;
		});
	},

	renderStatus: function (s) {
		var hsTxt = '—';
		if (s.hs_age != null) {
			hsTxt = s.hs_age < 180 ? (s.hs_age + ' сек назад') : 'старше 3 минут — туннель не отвечает';
		}
		var rows = [
			row('WARP.conf', s.conf_exists ? 'есть' : 'нет'),
			row('Интерфейс', s.iface_exists ? (s.iface || 'warp') + (s.iface_manual_off ? ' (выключен вручную)' : '') : 'не найден'),
			row('Точка входа', s.endpoint || '—'),
			row('Рукопожатие', hsTxt),
			row('Последняя проверка', fmtTime(s.last_check) + ' ', resultBadge(s.last_result), s.last_detail ? E('span', { 'class': 'wac-hint' }, ' ' + s.last_detail) : E('span')),
			row('Последняя замена', s.last_replace ? fmtTime(s.last_replace) : 'не было'),
			row('Автопроверка', s.enabled ? ('включена, каждые ' + s.interval + ' ч') : 'выключена')
		];
		if (s.running) {
			rows.push(row('Сейчас', E('span', { 'class': 'wac-busy' }, 'выполняется операция…')));
		}
		return E('div', { 'class': 'wac-card' }, [E('h3', {}, 'Статус')].concat(rows));
	},

	renderActions: function (s) {
		var self = this;
		var busy = !!s.running;
		var checkBtn = E('button', {
			'class': 'btn cbi-button cbi-button-positive',
			'disabled': busy ? '' : null,
			'click': ui.createHandlerFn(self, function () { return self.runAction(rpcCheck, 'Проверяем WARP'); })
		}, 'Проверить сейчас');
		var regenBtn = E('button', {
			'class': 'btn cbi-button cbi-button-negative',
			'disabled': busy ? '' : null,
			'click': ui.createHandlerFn(self, function () {
				return new Promise(function (resolve) {
					ui.showModal('Заменить WARP-конфиг?', E('p', {},
						'Роутер получит новые ключи WARP, переберёт точки входа и запишет рабочую связку в /root/WARP.conf. Это займёт до 10 минут, туннель переподнимется.'), [
						E('button', { 'class': 'btn', 'click': function () { ui.hideModal(); resolve(null); } }, 'Отмена'),
						E('button', { 'class': 'btn cbi-button-negative important', 'click': function () { ui.hideModal(); resolve(true); } }, 'Заменить')
					]);
				}).then(function (ok) { return ok ? self.runAction(rpcRegen, 'Генерируем WARP с проверкой') : undefined; });
			})
		}, 'Заменить сейчас');
		return E('div', { 'class': 'wac-card' }, [
			E('h3', {}, 'Действия'),
			E('div', { 'class': 'wac-actions' }, [checkBtn, regenBtn])
		]);
	},

	runAction: function (fn, busyText) {
		var self = this;
		ui.showIndicator(null, busyText, true);
		return fn().then(function (res) {
			ui.hideIndicator();
			if (res && res.error) {
				ui.addNotification(null, E('p', {}, res.error), 'error');
				return;
			}
			ui.addNotification(null, E('p', {}, 'Операция запущена'), 'info');
			self.startPolling(true);
		}).catch(function () {
			ui.hideIndicator();
			ui.addNotification(null, E('p', {}, 'Роутер не ответил'), 'error');
		});
	},

	startPolling: function (running) {
		var self = this;
		if (pollTimer) { clearTimeout(pollTimer); pollTimer = null; }
		if (!running) return;
		var tick = function () {
			rpcStatus().then(function (s) {
				if (!s) return;
				self.liveUpdate(s);
				if (s.running) {
					pollTimer = setTimeout(tick, 3000);
				} else {
					ui.addNotification(null, E('p', {}, 'Операция завершена'), 'info');
					self.refreshAll();
				}
			});
		};
		pollTimer = setTimeout(tick, 3000);
	},

	renderSettings: function (st) {
		var self = this;
		var enabled = E('input', { 'id': 'wac-enabled', 'type': 'checkbox', 'checked': st.enabled ? '' : null });
		var interval = E('input', { 'class': 'wac-input', 'id': 'wac-interval', 'type': 'number', 'min': '1', 'max': '168', 'value': String(st.interval || 6), 'style': 'width:6em' });
		var iface = E('input', { 'class': 'wac-input', 'id': 'wac-iface', 'type': 'text', 'value': st.interface || 'warp', 'style': 'width:12em' });
		var retries = E('select', { 'class': 'wac-input', 'id': 'wac-retries' }, [0, 1, 2, 3].map(function (n) {
			return E('option', { 'value': String(n), 'selected': (st.retries || 2) === n ? '' : null }, String(n));
		}));

		var card = E('div', { 'class': 'wac-card' }, [E('h3', {}, 'Настройки автопроверки')]);
		card.appendChild(row(E('label', {}, [enabled, ' Автопроверка включена']), E('span')));
		card.appendChild(row('Интервал, часов', [interval, E('div', { 'class': 'wac-hint' }, 'Раз в N часов проверять WARP (1–168)')]));
		card.appendChild(row('Интерфейс AmneziaWG', [iface, E('div', { 'class': 'wac-hint' }, 'Имя интерфейса, соответствующего WARP.conf')]));
		card.appendChild(row('Повторных проверок', [retries, E('div', { 'class': 'wac-hint' }, 'Сколько раз перепроверить перед заменой (0–3), пауза 5 минут')]));

		var saveBtn = E('button', {
			'class': 'btn cbi-button cbi-button-positive important',
			'click': ui.createHandlerFn(self, function () {
				var enabledVal = enabled.checked ? 1 : 0;
				var intervalVal = parseInt(interval.value, 10) || 0;
				var retriesVal = parseInt(retries.value, 10) || 0;
				return rpcSetSettings(String(enabledVal), String(intervalVal), (iface.value || '').trim(), String(retriesVal)).then(function (res) {
					if (res && res.error) {
						ui.addNotification(null, E('p', {}, res.error), 'error');
						return;
					}
					ui.addNotification(null, E('p', {}, 'Настройки сохранены'), 'info');
					self.refreshAll();
				});
			})
		}, 'Сохранить');
		card.appendChild(E('div', { 'class': 'wac-actions', 'style': 'margin-top:10px' }, saveBtn));
		return card;
	},

	updateSettingsCard: function (st) {
		/* живое обновление значений полей, если пользователь их не редактирует */
		var el = function (id) { return document.getElementById(id); };
		var en = el('wac-enabled'), iv = el('wac-interval'), ifc = el('wac-iface'), rt = el('wac-retries');
		if (!en || !iv || !ifc || !rt) { this.replaceCard('_settingsCard', this.renderSettings(st)); return; }
		en.checked = !!st.enabled;
		if (iv.value === '') iv.value = String(st.interval || 6);
		if (ifc.value === '') ifc.value = st.interface || 'warp';
		rt.value = String(st.retries || 2);
	},

	renderLog: function () {
		var self = this;
		var pre = E('pre', { 'class': 'wac-log' }, 'Загрузка…');
		this._logPre = pre;
		this.refreshLog();
		var btn = E('button', {
			'class': 'btn cbi-button',
			'click': ui.createHandlerFn(self, function () { return self.refreshLog(); })
		}, 'Обновить лог');
		return E('div', { 'class': 'wac-card' }, [
			E('h3', {}, 'Лог'),
			E('div', { 'class': 'wac-actions' }, btn),
			pre
		]);
	},

	refreshLog: function () {
		var pre = this._logPre;
		if (!pre) return Promise.resolve();
		return rpcLog().then(function (res) {
			pre.textContent = (res && res.content) || '(пусто)';
		}).catch(function () {
			pre.textContent = 'Не удалось получить лог';
		});
	},

	handleSaveApply: function () { return Promise.resolve(); },
	handleSave: function () { return Promise.resolve(); },
	handleReset: function () { return Promise.resolve(); }
});
