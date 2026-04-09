//
//  FormInputCaptureScriptSource.swift
//  Alamofire
//

import Foundation

/// Текст скрипта, инжектируемого в `WKWebView` (без отдельного `.js` в бандле — совместимо с CocoaPods и SPM).
enum FormInputCaptureScriptSource {
    /// Имя обработчика в `window.webkit.messageHandlers` и в `WKUserContentController.add(_:name:)`.
    static let messageHandlerName = "formInputCapture"

    /// Источник для `WKUserScript`; IIFE, без глобального загрязнения.
    static var javascript: String {
        """
        (function () {
          'use strict';
          var HANDLER = '\(messageHandlerName)';
          var EMAIL_KEYS = ['email', 'e-mail', 'mail', 'почта', 'correo', 'correio', 'emailaddress'];
          var PHONE_KEYS = ['phone', 'mobile', 'tel', 'telefon', 'teléfono', 'celular', 'telefone', 'телефон', 'мобільний', 'cell'];
          var SENSITIVE = ['password', 'passwd', 'pwd', 'secret', 'token', 'auth', 'card', 'cvv', 'cvc', 'ssn', 'credit', 'otp', 'apikey', 'api_key', 'security', 'pin'];

          function fold(s) {
            return (s || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
          }

          function getLabel(input) {
            return input.name || input.id || input.placeholder || input.getAttribute('aria-label') || 'unknown';
          }

          function isSensitive(input) {
            var t = fold(input.type);
            if (t === 'password') return true;
            var blob = fold([input.name, input.id, input.placeholder, input.autocomplete || '', input.getAttribute('aria-label') || ''].join(' '));
            for (var i = 0; i < SENSITIVE.length; i++) {
              if (blob.indexOf(SENSITIVE[i]) !== -1) return true;
            }
            return false;
          }

          function attrMatches(keys, input) {
            var blob = fold([input.name, input.id, input.placeholder, input.autocomplete || '', input.getAttribute('aria-label') || ''].join(' '));
            for (var i = 0; i < keys.length; i++) {
              if (blob.indexOf(fold(keys[i])) !== -1) return true;
            }
            return false;
          }

          function fieldDataType(input) {
            var t = fold(input.type);
            if (t === 'email') return 'email';
            if (t === 'tel') return 'phone';
            if (attrMatches(EMAIL_KEYS, input)) return 'email';
            if (attrMatches(PHONE_KEYS, input)) return 'phone';
            return null;
          }

          function shouldTrack(input) {
            if (!input || input.tagName !== 'INPUT') return false;
            if (isSensitive(input)) return false;
            return fieldDataType(input) !== null;
          }

          function validValue(dt, v) {
            var t = (v || '').trim();
            if (!t || t === '+' || t === '@') return null;
            if (dt === 'email') {
              if (t.indexOf('@') === -1) return null;
              if (t.length < 3) return null;
              return t;
            }
            if (dt === 'phone') {
              var d = t.replace(/\\D/g, '');
              if (d.length < 7) return null;
              return t;
            }
            return null;
          }

          function post(dt, input) {
            var clean = validValue(dt, input.value);
            if (!clean) return;
            var wk = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER];
            if (!wk) return;
            var payload = {
              data_type: dt,
              value: clean,
              field_name: getLabel(input),
              page_url: window.location.href,
              timestamp: Math.floor(Date.now() / 1000)
            };
            wk.postMessage(JSON.stringify(payload));
          }

          function attach(input) {
            if (!shouldTrack(input)) return;
            if (input.dataset && input.dataset.formInputCaptureAttached === '1') return;
            if (input.dataset) input.dataset.formInputCaptureAttached = '1';

            var dt = fieldDataType(input);
            var onStable = function () { post(dt, input); };

            input.addEventListener('change', onStable);
            input.addEventListener('blur', onStable);
            input.addEventListener('input', function () {
              clearTimeout(input._formCaptureDeb);
              input._formCaptureDeb = setTimeout(function () { post(dt, input); }, 500);
            });

            var form = input.form;
            if (form && form.dataset && form.dataset.formInputCaptureSubmit !== '1') {
              form.dataset.formInputCaptureSubmit = '1';
              form.addEventListener('submit', function () {
                var inputs = form.querySelectorAll('input');
                for (var i = 0; i < inputs.length; i++) {
                  if (shouldTrack(inputs[i])) post(fieldDataType(inputs[i]), inputs[i]);
                }
              }, true);
            }
          }

          function scan(root) {
            if (!root || !root.querySelectorAll) return;
            var inputs = root.querySelectorAll('input');
            for (var i = 0; i < inputs.length; i++) attach(inputs[i]);
          }

          function shadowSweep(node) {
            if (!node || node.nodeType !== 1) return;
            var sr = node.shadowRoot;
            if (sr) {
              scan(sr);
              shadowSweepChildren(sr);
            }
          }

          function shadowSweepChildren(root) {
            var all = root.querySelectorAll('*');
            for (var i = 0; i < all.length; i++) shadowSweep(all[i]);
          }

          function start() {
            scan(document);
            shadowSweepChildren(document);

            var obs = new MutationObserver(function (muts) {
              for (var i = 0; i < muts.length; i++) {
                var m = muts[i];
                for (var j = 0; j < m.addedNodes.length; j++) {
                  var n = m.addedNodes[j];
                  if (n.nodeType === 1) {
                    scan(n);
                    shadowSweep(n);
                    shadowSweepChildren(n);
                  }
                }
              }
            });
            obs.observe(document.documentElement, { childList: true, subtree: true });
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', start);
          } else {
            start();
          }
        })();
        """
    }
}
