// Client-side behavior for the CFB Spread Predictor.
// Picker logic lives here so the pickers never re-render on the server:
// rendering team options, keeping a team from being picked twice, swapping,
// and the site labels. Also: copy to clipboard, logo fallback, slate clicks.
(function () {
  'use strict';

  // Team options -------------------------------------------------------------

  function escapeHtml(text) {
    return String(text == null ? '' : text).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  // Same markup as team_badge() in R/ui_helpers.R.
  function badge(team) {
    var logo = team.logo
      ? '<img class="team-logo" src="' + escapeHtml(team.logo) + '" alt="' + escapeHtml(team.school) + ' logo">'
      : '';
    return '<span class="team-badge team-badge-sm' + (team.logo ? ' has-logo' : '') + '"' +
      ' style="--badge-bg:' + escapeHtml(team.bg) + ';--badge-fg:' + escapeHtml(team.fg) + '">' +
      '<span class="team-initials" aria-hidden="true">' + escapeHtml(team.initials) + '</span>' + logo +
      '</span>';
  }

  // Used by selectize through the `render` option set in R/mod_matchup.R.
  window.cfbTeamRender = {
    option: function (team, escape) {
      var meta = [team.mascot, team.abbreviation].filter(Boolean).map(escape).join(' &middot; ');
      // selectize needs the "option" and "item" classes on its templates.
      return '<div class="option team-option">' + badge(team) +
        '<span class="team-option-text"><span class="team-option-school">' + escape(team.school) + '</span>' +
        (meta ? '<span class="team-option-meta">' + meta + '</span>' : '') + '</span></div>';
    },
    item: function (team, escape) {
      return '<div class="item team-item">' + badge(team) + '<span>' + escape(team.school) + '</span></div>';
    }
  };

  // A logo that fails to load is removed, revealing the initials beneath it.
  document.addEventListener('error', function (event) {
    var img = event.target;
    if (img && img.classList && img.classList.contains('team-logo')) {
      if (img.parentNode) img.parentNode.classList.remove('has-logo');
      img.remove();
    }
  }, true);

  // Picker pairs -------------------------------------------------------------

  // A pair is the two team pickers plus the site radios in one container.
  function getPair(container) {
    var a = document.getElementById(container.dataset.teamA);
    var b = document.getElementById(container.dataset.teamB);
    if (!a || !b || !a.selectize || !b.selectize) return null;
    if (!container._allOptions) {
      // Snapshot every team once, so options removed from one side can come back.
      container._allOptions = $.extend(true, {}, a.selectize.options);
      makeSearchable(a.selectize);
      makeSearchable(b.selectize);
    }
    return { container: container, a: a.selectize, b: b.selectize, all: container._allOptions };
  }

  // A single-select selectize ignores typing until its item is deleted. Clear
  // the box quietly on focus so people can just start typing, and put the
  // team back if they leave without choosing. Both steps are silent, so the
  // server never sees the empty value.
  function makeSearchable(picker) {
    picker.on('focus', function () {
      picker._previous = picker.getValue();
      picker.clear(true);
    });
    picker.on('blur', function () {
      if (!picker.getValue() && picker._previous) picker.setValue(picker._previous, true);
    });
  }

  // Each side offers every team except the one picked on the other side.
  function syncExclusions(pair) {
    var valueA = pair.a.getValue();
    var valueB = pair.b.getValue();
    [[pair.a, valueB], [pair.b, valueA]].forEach(function (entry) {
      var picker = entry[0];
      var excluded = entry[1];
      Object.keys(pair.all).forEach(function (value) {
        if (value === excluded) {
          if (picker.options[value]) picker.removeOption(value, true);
        } else if (!picker.options[value]) {
          picker.addOption(pair.all[value]);
        }
      });
      picker.refreshOptions(false);
    });
    updateSiteLabels(pair);
  }

  // "<A> home" and "<B> home" follow the picked teams.
  function updateSiteLabels(pair) {
    var names = { a: pair.all[pair.a.getValue()], b: pair.all[pair.b.getValue()] };
    pair.container.querySelectorAll('.site-team').forEach(function (span) {
      var team = names[span.dataset.side];
      if (team) span.textContent = team.school;
    });
  }

  function siteRadios(pair) {
    return pair.container.querySelectorAll('input[name="' + pair.container.dataset.site + '"]');
  }

  function getSite(pair) {
    var checked = Array.prototype.find.call(siteRadios(pair), function (r) { return r.checked; });
    return checked ? checked.value : 'neutral';
  }

  function setSite(pair, site) {
    siteRadios(pair).forEach(function (radio) {
      if (radio.value === site && !radio.checked) {
        radio.checked = true;
        $(radio).trigger('change');
      }
    });
  }

  // Set all three inputs at once. Shiny batches the changes into one update,
  // so the prediction recomputes once and nothing flickers.
  var settingPair = false;
  function setMatchup(pair, a, b, site) {
    settingPair = true;
    try {
      Object.keys(pair.all).forEach(function (value) {
        if (!pair.a.options[value]) pair.a.addOption(pair.all[value]);
        if (!pair.b.options[value]) pair.b.addOption(pair.all[value]);
      });
      pair.a.setValue(String(a));
      pair.b.setValue(String(b));
      setSite(pair, site);
    } finally {
      settingPair = false;
    }
    syncExclusions(pair);
  }

  function initPairs() {
    document.querySelectorAll('[data-team-a]').forEach(function (container) {
      var pair = getPair(container);
      if (pair) syncExclusions(pair);
    });
  }

  $(document).on('shiny:connected', initPairs);

  $(document).on('change', '[data-team-a] select', function () {
    if (settingPair) return;
    var pair = getPair(this.closest('[data-team-a]'));
    if (pair) syncExclusions(pair);
  });

  // Swap keeps the home team the same school, so the site flips sides.
  $(document).on('click', '[data-swap]', function () {
    var pair = getPair(document.getElementById(this.dataset.swap));
    if (!pair) return;
    var flip = { a_home: 'b_home', b_home: 'a_home', neutral: 'neutral' };
    setMatchup(pair, pair.b.getValue(), pair.a.getValue(), flip[getSite(pair)]);
  });

  // Loading a matchup from the server (for example, a slate row).
  function onSetMatchup(msg) {
    var pair = getPair(document.getElementById(msg.container));
    if (pair) setMatchup(pair, msg.a, msg.b, msg.site);
  }

  // Copy summary ---------------------------------------------------------------

  function onSummary(msg) {
    var button = document.getElementById(msg.id);
    if (button) button.dataset.summary = msg.text;
  }

  // Older browsers and non-secure pages have no clipboard API.
  function copyWithTextarea(text) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(area);
    return ok ? Promise.resolve() : Promise.reject(new Error('copy failed'));
  }

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).catch(function () { return copyWithTextarea(text); });
    }
    return copyWithTextarea(text);
  }

  function flashLabel(button, text, state) {
    var label = button.querySelector('.btn-copy-label');
    clearTimeout(button._resetTimer);
    label.textContent = text;
    button.classList.add(state);
    button._resetTimer = setTimeout(function () {
      label.textContent = 'Copy summary';
      button.classList.remove('is-copied', 'is-failed');
    }, 1800);
  }

  $(document).on('click', '.btn-copy', function () {
    var button = this;
    copyText(button.dataset.summary || '').then(
      function () { flashLabel(button, 'Copied', 'is-copied'); },
      function () { flashLabel(button, 'Could not copy', 'is-failed'); }
    );
  });

  // This week: open a game ----------------------------------------------------

  // The whole row is clickable; the Open button inside it carries the game id
  // and keeps it reachable by keyboard.
  $(document).on('click', '.slate-table tbody tr', function () {
    var button = this.querySelector('[data-game-id]');
    if (!button || !window.Shiny) return;
    Shiny.setInputValue(button.dataset.input, Number(button.dataset.gameId), { priority: 'event' });
  });

  // When a tab changes, start at the top so the answer is in view.
  $(document).on('shown.bs.tab', function () { window.scrollTo(0, 0); });

  $(document).on('shiny:connected', function () {
    Shiny.addCustomMessageHandler('cfb-set-matchup', onSetMatchup);
    Shiny.addCustomMessageHandler('cfb-summary', onSummary);
  });
})();
