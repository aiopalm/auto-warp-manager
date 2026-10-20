'use strict';
'require view';
'require rpc';
'require ui';

var rpcStatus = rpc.declare({ object: 'luci.warp-autocheck', method: 'status' });
var rpcCheck = rpc.declare({ object: 'luci.warp-autocheck', method: 'check' });
var rpcRegen = rpc.declare({ object: 'luci.warp-autocheck', method: 'regen' });
var rpcLog = rpc.declare({ object: 'luci.warp-autocheck', method: 'log' });
var rpcGetSettings = rpc.declare({ object: 'luci.warp-autocheck', method: 'get_settings' });
var rpcSetSettings = rpc.declare({ object: 'luci.warp-autocheck', method: 'set_settings' });

var pollTimer = null;

function fmtTime(ts) {
	if (!ts || ts === 0) return '—';
	var d = new Date(ts * 1000);
	return d.toLocaleString();
}

function resultBadge(res) {
	var map = {
		ok:        ['success', 'работает'],
		'replaced': ['success', 'заменён и работает'],
		'no-link': ['danger', 'нет связи'],
		torn:      ['warning', 'обрывается (DPI)'],
		'ru-colo': ['warning', 'российский узел'],
		'no-iface': ['danger', 'интерфейс не найден'],
		'manual-off': ['muted', 'выключен вручную'],
		'wan-down': ['muted', 'сеть недоступна'],
		'no-conf': ['danger', 'конфиг не найден'],
		'not-helped': ['warning', 'замена не помогла'],
		'regen-failed': ['danger', 'регенерация не удалась'],
		'rolled-back': ['warning', 'заменён и откачен'],
		none: ['muted', 'ещё не проверялся']
	};
	var m = map[res] || ['muted', res || '—'];
	return E('span', { 'class': 'label label-' + m[0] }, m[1]);
}

return view.extend({
	handleSaveApply: null,

	load: function () {
		return Promise.all([rpcStatus(), rpcGetSettings()]);
	},

	render: function (data) {
		var status = data[0] || {};
		var settings = data[1] || {};
		var container = E('div', { 'class': 'cbi-map' });
		var self = this;

		if (!status.conf_exists) {
			container.appendChild(E('div', { 'class': 'cbi-map' }, [
				E('h3', {}, 'WARP AutoCheck'),
				E('div', { 'class': 'alert-message danger' },
					'WARP-конфиг не найден (/root/WARP.conf). Сгенерируйте WARP-конфиг в Zapret Manager (раздел AmneziaWG) и импортируйте его как интерфейс.'
				)
			]));
			return container;
		}

		container.appendChild(this.renderStatus(status));
		container.appendChild(this.renderActions(status));
		container.appendChild(this.renderSettings(settings));
		container.appendChild(this.renderLog());

		this.startPolling(status.running);
		return container;
	},

	renderStatus: function (s) {
		var rows = [
			_('WARP.conf'), s.conf_exists ? _('есть') : _('нет'),
			_('Интерфейс'), (s.iface_exists ? (s.iface || 'warp') + (s.iface_manual_off ? ' (' + _('выключен вручную') + ')' : '') : _('не найден')),
			_('Точка входа'), s.endpoint || '—',
			_('Рукопожатие'), s.hs_age != null ? (s.hs_age < 180 ? _('%d сек назад').format(s.hs_age) : _('старше 3 минут — туннель не отвечает')) : '—',
			_('Последняя проверка'), fmtTime(s.last_check) + ' — ' + resultBadge(s.last_result) + (s.last_detail ? ' (' + s.last_detail + ')' : ''),
			_('Последняя замена'), s.last_replace ? fmtTime(s.last_replace) : _('не было'),
			_('Автопроверка'), s.enabled ? _('включена, каждые %d ч').format(s.interval) : _('выключена')
		];
		var table = E('table', { 'class': 'table' });
		for (var i = 0; i < rows.length; i += 2) {
			table.appendChild(E('tr', {}, [
				E('td', { 'style': 'width:33%' }, '' + rows[i]),
				E('td', {}, E('strong', {}, '' + rows[i + 1]))
			]));
		}
		return E('div', { 'class': 'cbi-map' }, [
			E('h3', {}, _('Статус')),
			table
		]);
	},

	renderActions: function (s) {
		var self = this;
		var busy = !!s.running;
		var box = E('div', { 'class': 'cbi-page-actions' });
		var checkBtn = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'disabled': busy ? '' : null,
			'click': ui.createHandlerFn(self, function () { return self.runAction(rpcCheck, 'Проверяем WARP'); })
		}, _('Проверить сейчас'));
		var regenBtn = E('button', {
			'class': 'btn cbi-button cbi-button-negative',
			'disabled': busy ? '' : null,
			'click': ui.createHandlerFn(self, function () {
				return new Promise(function (resolve) {
					ui.showModal(_('Заменить WARP-конфиг?'), E('p', {},
						_('Роутер получит новые ключи WARP, переберёт точки входа и запишет рабочую связку в /root/WARP.conf. Это займёт до 10 минут, туннель переподнимется.')), [
						E('button', { 'class': 'btn', 'click': function () { ui.hideModal(); resolve(null); } }, _('Отмена')),
						E('button', { 'class': 'btn cbi-button-negative important', 'click': function () { ui.hideModal(); resolve(true); } }, _('Заменить'))
					]);
				}).then(function (ok) { return ok ? self.runAction(rpcRegen, 'Генерируем WARP с проверкой') : undefined; });
			})
		}, _('Заменить сейчас'));
		box.appendChild(checkBtn);
		box.appendChild(E('span', { 'style': 'margin-right:1em' }));
		box.appendChild(regenBtn);
		return E('div', { 'class': 'cbi-map' }, [E('h3', {}, _('Действия')), box]);
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
			ui.addNotification(null, E('p', {}, _('Операция запущена — следите за статусом')), 'info');
			self.startPolling(true);
		}).catch(function (e) {
			ui.hideIndicator();
			ui.addNotification(null, E('p', {}, _('Роутер не ответил')), 'error');
		});
	},

	startPolling: function (running) {
		var self = this;
		if (pollTimer) { clearTimeout(pollTimer); pollTimer = null; }
		if (!running) return;
		var tick = function () {
			rpcStatus().then(function (s) {
				if (s && s.running) {
					pollTimer = setTimeout(tick, 3000);
				} else {
					ui.addNotification(null, E('p', {}, _('Операция завершена')), 'info');
					self.redraw();
				}
			});
		};
		pollTimer = setTimeout(tick, 3000);
	},

	redraw: function () {
		// LuCI-view перерисовка: надёжнее перезагрузить страницу после долгой операции
		window.location.reload();
	},

	renderSettings: function (st) {
		var self = this;
		var box = E('div', { 'class': 'cbi-map' }, [E('h3', {}, _('Настройки автопроверки'))]);
		var table = E('table', { 'class': 'table' });

		var enabled = E('input', { 'type': 'checkbox', 'checked': st.enabled ? '' : null });
		var interval = E('input', { 'type': 'number', 'min': '1', 'max': '168', 'value': String(st.interval || 6), 'style': 'width:6em' });
		var iface = E('input', { 'type': 'text', 'value': st.interface || 'warp', 'style': 'width:12em' });
		var retries = E('select', {}, [0, 1, 2, 3].map(function (n) {
			return E('option', { 'value': String(n), 'selected': (st.retries || 2) === n ? '' : null }, String(n));
		}));

		var addRow = function (label, control, hint) {
			table.appendChild(E('tr', {}, [
				E('td', { 'style': 'width:33%' }, label),
				E('td', {}, [control, hint ? E('div', { 'class': 'cbi-value-description' }, hint) : E('span')])
			]));
		};
		addRow(_('Автопроверка включена'), enabled);
		addRow(_('Интервал, часов'), interval, _('Раз в N часов проверять WARP (1–168)'));
		addRow(_('Интерфейс AmneziaWG'), iface, _('Имя интерфейса, соответствующего WARP.conf'));
		addRow(_('Повторных проверок'), retries, _('Сколько раз перепроверить перед заменой (0–3), пауза 5 минут'));

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
					ui.addNotification(null, E('p', {}, _('Настройки сохранены')), 'info');
					setTimeout(function () { self.redraw(); }, 500);
				});
			})
		}, _('Сохранить'));

		box.appendChild(table);
		box.appendChild(E('div', { 'class': 'cbi-page-actions' }, saveBtn));
		return box;
	},

	renderLog: function () {
		var self = this;
		var pre = E('pre', { 'class': 'cbi-map', 'style': 'max-height:300px; overflow:auto; font-size:12px' }, _('Загрузка…'));
		rpcLog().then(function (res) {
			var content = (res && res.content) || '(пусто)';
			pre.textContent = content;
		}).catch(function () {
			pre.textContent = _('Не удалось получить лог');
		});
		var btn = E('button', {
			'class': 'btn cbi-button',
			'click': ui.createHandlerFn(self, function () {
				return rpcLog().then(function (res) { pre.textContent = (res && res.content) || '(пусто)'; });
			})
		}, _('Обновить лог'));
		return E('div', { 'class': 'cbi-map' }, [
			E('h3', {}, _('Лог')),
			btn,
			pre
		]);
	},

	handleSaveApply: function () { return Promise.resolve(); },
	handleSave: function () { return Promise.resolve(); },
	handleReset: function () { return Promise.resolve(); }
});
