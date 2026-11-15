// Copyright (C) 2026 Nobuto Kaitoh
// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of yamada. See LICENSE for the license text.

// Executed only inside the editor-owned figure window.
(() => {
    const cfg = CFG;
    // Resolve to false instead of waiting forever when a browser pauses the awaited work.
    const bounded = (promise, milliseconds) => Promise.race([
        promise.then(() => true),
        new Promise(resolve => setTimeout(() => resolve(false), milliseconds))
    ]);
    require(['mw-messageservice/MessageService'], function (bus) {
        const send = data => bus.publish(cfg.channel, Object.assign({token: cfg.token}, data));
        (async () => {
            // Force the pending style and layout pass, then let queued view work run.
            document.body.getBoundingClientRect();
            await new Promise(resolve => setTimeout(resolve));
            // Image loads can resize fit layouts after the frame that started them.
            const pending = Array.from(document.images).filter(image => !image.complete).map(image =>
                new Promise(resolve => {
                    image.addEventListener('load', resolve, {once: true});
                    image.addEventListener('error', resolve, {once: true});
                }));
            const imagesLoaded = await bounded(Promise.all(pending), cfg.limit);
            // One animation frame runs after the callbacks that relayout grid children.
            document.body.getBoundingClientRect();
            const framed = await bounded(new Promise(resolve => window.requestAnimationFrame(resolve)), cfg.limit);
            send({imagesWaited: pending.length, imagesLoaded: imagesLoaded, framed: framed});
        })().catch(error => send({error: String(error)}));
    }, error => {
        require('mw-messageservice/MessageService').publish(cfg.channel, {
            token: cfg.token, error: String(error)
        });
    });
    return cfg.token;
})()
