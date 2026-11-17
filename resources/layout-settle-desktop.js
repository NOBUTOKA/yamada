// Copyright (C) 2026 Nobuto Kaitoh
// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of yamada. See LICENSE for the license text.

// Runs once per MATLAB session in the desktop page through a temporary RootApp panel.
// It installs a resident receiver that accepts only request data, never script text.
(() => {
    const install = INSTALL;
    const template = SCRIPT;
    const receiver = window.__yamadaLayoutReceiver || (window.__yamadaLayoutReceiver = {});
    const hasControllers = (page, channel) => {
        try {
            if (page.closed) { return false; }
            const service = page.require('MW/componentframework/ControllerService');
            // A lookup must not create an empty service in unrelated pages.
            const cache = service._instances?.[channel]?.service?._controllerCache;
            return cache instanceof Map ? cache.size > 0 : Object.keys(cache || {}).length > 0;
        } catch {
            return false;
        }
    };
    // Find the one page that renders the figure and run the settle script there.
    const dispatch = (bus, cfg, started) => {
        const children = Object.values(window.ChildWindowManager?._childInfo || {});
        const pages = [...new Set([window, ...children.map(entry => entry.window).filter(Boolean)])];
        const matches = pages.filter(page => hasControllers(page, cfg.figureChannel));
        if (matches.length !== 1) {
            // The desktop can still be attaching or moving the figure between pages.
            if (performance.now() - started < 2000) {
                setTimeout(() => dispatch(bus, cfg, started), 25);
            } else {
                bus.publish(cfg.channel, {
                    token: cfg.token, error: 'Could not locate a unique desktop page for the figure channel.'
                });
            }
            return;
        }
        // The configuration is inserted as a JSON literal, so request data cannot add code.
        const doc = matches[0].document;
        const tag = doc.createElement('script');
        tag.textContent = receiver.template.split('CFG').join(JSON.stringify(cfg));
        doc.head.appendChild(tag);
        tag.remove();
    };
    // Validate the request shape before any page is searched.
    const handle = (bus, message) => {
        const cfg = message && message.data;
        const fields = ['channel', 'token', 'event', 'figure', 'figureChannel'];
        if (!cfg || fields.some(field => typeof cfg[field] !== 'string')) { return; }
        dispatch(bus, cfg, performance.now());
    };
    require(['mw-messageservice/MessageService'], bus => {
        // A reinstall replaces the template and handler but keeps one subscription.
        receiver.template = template;
        receiver.handle = message => handle(bus, message);
        const ready = receiver.channel === install.requests ? Promise.resolve() :
            Promise.resolve(bus.subscribe(install.requests, message => receiver.handle(message))).then(() => {
                receiver.channel = install.requests;
            });
        // Acknowledge only after the subscription is registered, so the first request is delivered.
        ready.then(() => bus.publish(install.channel, {token: install.token, installed: true}),
            error => bus.publish(install.channel, {token: install.token, error: String(error)}));
    });
})();
