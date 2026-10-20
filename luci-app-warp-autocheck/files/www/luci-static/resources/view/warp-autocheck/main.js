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
	'.wac-wrap { width: 100%; }',
	'.wac-grid { display: grid; grid-template-columns: minmax(300px, 420px) 1fr; gap: 14px; align-items: start; }',
	'.wac-col { min-width: 0 }',
	'@media (max-width: 900px) { .wac-grid { grid-template-columns: 1fr } }',
	'.wac-card { background: var(--surface-2, rgba(127,127,127,.06)); border: 1px solid var(--border, rgba(127,127,127,.22)); border-radius: 16px; padding: 14px 18px; margin-bottom: 14px; }',
	'.wac-card h3 { margin: 0 0 10px 0; font-size: 1.05rem; }',
	'.wac-row { display: flex; align-items: baseline; gap: 12px; padding: 4px 0; border-bottom: 1px solid rgba(127,127,127,.18); flex-wrap: wrap; }',
	'.wac-row:last-child { border-bottom: 0 }',
	'.wac-key { width: 200px; min-width: 140px; opacity: .65; flex-shrink: 0 }',
	'.wac-val { flex: 1; min-width: 0; word-break: break-word; overflow-wrap: anywhere }',
	'.wac-val .wac-input, .wac-val select, .wac-val input { max-width: 100%; box-sizing: border-box }',
	'.wac-col { min-width: 0; display: flex; flex-direction: column }',
	'.wac-col .wac-card:last-child { flex: 1; margin-bottom: 0 }',
	'.wac-badge { display: inline-flex; align-items: center; padding: 2px 11px; border-radius: 999px; font-size: 12px; font-weight: 600; white-space: nowrap; color: #fff; background: #888; }',
	'.wac-badge.wac-ok { background: #2e9e44 }',
	'.wac-badge.wac-warn { background: #d09a2e }',
	'.wac-badge.wac-bad { background: #c9302c }',
	'.wac-badge.wac-mute { background: #7f8c9b }',
	'.wac-alert { border-left: 4px solid #c9302c; padding: 10px 14px; border-radius: 12px; background: rgba(201,48,44,.14); }',
	'.wac-actions { display: flex; gap: 10px; flex-wrap: wrap; align-items: center }',
	'.wac-log { max-height: 300px; overflow: auto; font-size: 12px; white-space: pre-wrap; word-break: break-all; background: var(--surface-2, rgba(127,127,127,.10)); border: 1px solid var(--border, rgba(127,127,127,.16)); border-radius: 12px; padding: 10px; margin-top: 8px; }',
	'.wac-input { padding: 3px 8px; background: var(--surface-2, rgba(127,127,127,.1)); border: 1px solid var(--border, rgba(127,127,127,.3)); border-radius: 8px; color: inherit }',
	'.wac-hint { font-size: 12px; opacity: .6; margin-top: 2px }',
	'.wac-busy { display: inline-flex; align-items: center; padding: 2px 11px; border-radius: 999px; font-size: 12px; font-weight: 600; color: #fff; background: #356ac3; }'
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

function row(key) {
	var flat = [];
	for (var i = 1; i < arguments.length; i++) {
		var a = arguments[i];
		if (Array.isArray(a)) { flat = flat.concat(a); } else { flat.push(a); }
	}
	return E('div', { 'class': 'wac-row' }, [
		E('div', { 'class': 'wac-key' }, key),
		E('div', { 'class': 'wac-val' }, flat)
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

		this._actionsCard = this.renderActions(status);
		this._settingsCard = this.renderSettings(settings);
		this._statusCard = this.renderStatus(status);
		this._logCard = this.renderLog();

		/* действия — во всю ширину; ниже две колонки: слева настройки, справа статус+лог */
		wrap.appendChild(this._actionsCard);
		var leftCol = E('div', { 'class': 'wac-col' }, this._settingsCard);
		var rightCol = E('div', { 'class': 'wac-col' }, [this._statusCard, this._logCard]);
		wrap.appendChild(E('div', { 'class': 'wac-grid' }, [leftCol, rightCol]));

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
			'click': ui.createHandlerFn(self, function () { return self.runAction(rpcCheck); })
		}, 'Проверить сейчас');
		/* вкл/выкл автопроверки — зелёная «Включить» либо красная «Выключить» */
		var toggleBtn = E('button', {
			'class': 'btn cbi-button ' + (s.enabled ? 'cbi-button-negative' : 'cbi-button-positive'),
			'disabled': busy ? '' : null,
			'click': ui.createHandlerFn(self, function () {
				var newVal = s.enabled ? '0' : '1';
				var iv = document.getElementById('wac-interval');
				var ifc = document.getElementById('wac-iface');
				var rt = document.getElementById('wac-retries');
				var interval = iv ? (parseInt(iv.value, 10) || 6) : ((self._settings && self._settings.interval) || 6);
				var iface = ifc ? (ifc.value || 'warp').trim() : ((self._settings && self._settings.interface) || 'warp');
				var retries = rt ? (parseInt(rt.value, 10) || 0) : ((self._settings && self._settings.retries) || 2);
				return rpcSetSettings(newVal, String(interval), iface, String(retries)).then(function (res) {
					if (res && res.error) {
						ui.addNotification(null, E('p', {}, res.error), 'error');
						return;
					}
					return self.refreshAll();
				});
			})
		}, s.enabled ? 'Выключить' : 'Включить');
		var regenBtn = E('button', {
			'class': 'btn cbi-button cbi-button-negative',
			'disabled': busy ? '' : null,
			'click': function (ev) {
				ev.preventDefault();
				if (busy) return;
				ui.showModal('Заменить WARP-конфиг?', E('p', {},
					'Роутер получит новые ключи WARP, переберёт точки входа и запишет рабочую связку в /root/WARP.conf. Это займёт до 10 минут, туннель переподнимется.'), [
					E('button', { 'class': 'btn', 'click': function () { ui.hideModal(); } }, 'Отмена'),
					E('button', {
						'class': 'btn cbi-button-negative important',
						'click': function () { ui.hideModal(); self.runAction(rpcRegen); }
					}, 'Заменить')
				]);
			}
		}, 'Заменить сейчас');
		return E('div', { 'class': 'wac-card' }, [
			E('h3', {}, 'Действия'),
			E('div', { 'class': 'wac-actions' }, [toggleBtn, checkBtn, regenBtn])
		]);
	},

	runAction: function (fn) {
		var self = this;
		return fn().then(function (res) {
			if (res && res.error) {
				ui.addNotification(null, E('p', {}, res.error), 'error');
			}
			self.startPolling(true);
		}).catch(function () {
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
					self.refreshAll();
				}
			});
		};
		pollTimer = setTimeout(tick, 3000);
	},

	renderSettings: function (st) {
		var self = this;
		var interval = E('input', { 'class': 'wac-input', 'id': 'wac-interval', 'type': 'number', 'min': '1', 'max': '168', 'value': String(st.interval || 6), 'style': 'width:7em' });
		var iface = E('input', { 'class': 'wac-input', 'id': 'wac-iface', 'type': 'text', 'value': st.interface || 'warp', 'style': 'width:12em' });
		var retries = E('select', { 'class': 'wac-input', 'id': 'wac-retries' }, [0, 1, 2, 3].map(function (n) {
			return E('option', { 'value': String(n), 'selected': (st.retries || 2) === n ? '' : null }, String(n));
		}));

		var card = E('div', { 'class': 'wac-card' }, [E('h3', {}, 'Настройки автопроверки')]);
		card.appendChild(row('Интервал, часов', [interval, E('div', { 'class': 'wac-hint' }, 'Раз в N часов проверять WARP (1–168)')]));
		card.appendChild(row('Интерфейс AmneziaWG', [iface, E('div', { 'class': 'wac-hint' }, 'Имя интерфейса, соответствующего WARP.conf')]));
		card.appendChild(row('Повторных проверок', [retries, E('div', { 'class': 'wac-hint' }, 'Сколько раз перепроверить перед заменой (0–3), пауза 5 минут')]));

		var saveBtn = E('button', {
			'class': 'btn cbi-button cbi-button-positive important',
			'click': ui.createHandlerFn(self, function () {
				var intervalVal = parseInt(interval.value, 10) || 0;
				var retriesVal = parseInt(retries.value, 10) || 0;
				return rpcSetSettings(String(st.enabled ? 1 : 0), String(intervalVal), (iface.value || '').trim(), String(retriesVal)).then(function (res) {
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
		var iv = el('wac-interval'), ifc = el('wac-iface'), rt = el('wac-retries');
		if (!iv || !ifc || !rt) { this.replaceCard('_settingsCard', this.renderSettings(st)); return; }
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
