// Copyright (C) 2026 Nobuto Kaitoh
// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of yamada. See LICENSE for the license text.

// Runs in the desktop page through a temporary RootApp panel.
(() => {
    const cfg = CFG;
    const script = SCRIPT;
    const started = performance.now();
    const hasControllers = page => {
        try {
            if (page.closed) { return false; }
            const service = page.require('MW/componentframework/ControllerService');
            // A lookup must not create an empty service in unrelated pages.
            const cache = service._instances?.[cfg.figureChannel]?.service?._controllerCache;
            return cache instanceof Map ? cache.size > 0 : Object.keys(cache || {}).length > 0;
        } catch {
            return false;
        }
    };
    const dispatch = () => {
        const children = Object.values(window.ChildWindowManager?._childInfo || {});
        const pages = [...new Set([window, ...children.map(entry => entry.window).filter(Boolean)])];
        const matches = pages.filter(hasControllers);
        if (matches.length !== 1) {
            // The desktop can still be attaching or moving the figure between pages.
            if (performance.now() - started < 2000) {
                setTimeout(dispatch, 25);
            } else {
                require(['mw-messageservice/MessageService'], bus => bus.publish(cfg.channel, {
                    token: cfg.token, error: 'Could not locate a unique desktop page for the figure channel.'
                }));
            }
            return;
        }
        const doc = matches[0].document;
        const tag = doc.createElement('script');
        tag.textContent = script;
        doc.head.appendChild(tag);
        tag.remove();
    };
    dispatch();
})();
