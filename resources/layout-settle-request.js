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
    const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
    // Report failures that happen before the figure ViewModel is reachable.
    const fail = error => require(['mw-messageservice/MessageService'], bus => bus.publish(cfg.channel, {
        token: cfg.token, error: String(error)
    }));
    require(['viewmodel/impl/ViewModelManagerFactory', 'MW/componentframework/ControllerService'], function (factory, service) {
        try {
            const managers = Object.values(factory._viewModelManagerCache || {}).filter(manager => manager.hasById(cfg.figure));
            if (managers.length !== 1) { throw new Error('Expected exactly one ViewModel manager for the figure.'); }
            const manager = managers[0];
            const figureViewModel = manager.getById(cfg.figure);
            // Replies follow the client's position events on the figure ViewModel channel,
            // so MATLAB handles every event dispatched before the reply first.
            const send = data => figureViewModel.dispatchEvent(cfg.event, figureViewModel, Object.assign({token: cfg.token}, data));
            (async () => {
                // Record when any container last told its children that their client area changed.
                const resize = window.__yamadaLayoutResize || (window.__yamadaLayoutResize = {last: performance.now()});
                // The channel-wide controller cache exists in R2023a through R2026b; the figure
                // controller's _controllerMap is absent in R2023a and R2026b.
                const cache = service.getInstance(cfg.figureChannel)._controllerCache || {};
                const controllers = cache instanceof Map ? Array.from(cache.values()) : Object.values(cache);
                let hooked = 0;
                let watched = 0;
                for (const controller of controllers) {
                    if (!controller || typeof controller.emitContainerResizeControllerEvent !== 'function') { continue; }
                    watched++;
                    if (controller.__yamadaResizeHook) { continue; }
                    const original = controller.emitContainerResizeControllerEvent;
                    controller.emitContainerResizeControllerEvent = function (...args) {
                        resize.last = performance.now();
                        return original.apply(this, args);
                    };
                    controller.__yamadaResizeHook = true;
                    hooked++;
                }
                // Resizes before a controller was hooked are unknown, so treat them as just happened.
                if (hooked > 0) { resize.last = performance.now(); }
                // Force the pending style and layout pass, then let queued view work run.
                document.body.getBoundingClientRect();
                await delay(0);
                // Grid Layouts receive these resizes through a throttled handler whose trailing call
                // runs on a timer that neither stabilize() nor an animation frame observes; see
                // waitForPreviewLayout for the delay this quiet period covers.
                const started = performance.now();
                while (performance.now() - resize.last < cfg.quiet && performance.now() - started < cfg.quietLimit) {
                    await delay(10);
                }
                const quieted = performance.now() - resize.last >= cfg.quiet;
                // Image loads can resize fit layouts after the frame that started them.
                const pending = Array.from(document.images).filter(image => !image.complete).map(image =>
                    new Promise(resolve => {
                        image.addEventListener('load', resolve, {once: true});
                        image.addEventListener('error', resolve, {once: true});
                    }));
                const imagesLoaded = await bounded(Promise.all(pending), cfg.limit);
                // Await relayouts queued by the throttled handlers; R2023a has no stabilize().
                const root = manager.getRoot();
                const stabilized = typeof root.stabilize === 'function' ? await bounded(root.stabilize(), cfg.limit) : false;
                // One animation frame runs after the callbacks that relayout grid children.
                document.body.getBoundingClientRect();
                const framed = await bounded(new Promise(resolve => window.requestAnimationFrame(resolve)), cfg.limit);
                send({hooked: hooked, watched: watched, imagesWaited: pending.length, imagesLoaded: imagesLoaded, quieted: quieted,
                    stabilized: stabilized, framed: framed});
            })().catch(error => send({error: String(error)}));
        } catch (error) {
            fail(error);
        }
    }, fail);
    return cfg.token;
})()
