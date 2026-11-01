// Executed only inside the editor-owned R2024a figure window.
(() => {
    const cfg = CFG;
    require([
        'viewmodel/impl/ViewModelManagerFactory',
        'mw-messageservice/MessageService'
    ], function (factory, bus) {
        const send = data => bus.publish(cfg.channel, Object.assign({token: cfg.token}, data));
        (async () => {
            const managers = Object.values(factory._viewModelManagerCache || {})
                .filter(manager => manager.hasById(cfg.target));
            if (managers.length !== 1) {
                throw new Error('Expected exactly one owning Preview manager.');
            }
            // Await registered work throughout the owning container, including descendants.
            const root = managers[0].getRoot();
            await root.stabilize();
            if (root.hasAsyncOperations()) {
                throw new Error('Preview became unstable before acknowledgement.');
            }
            send({rootId: root.getId(), targetId: cfg.target});
        })().catch(error => send({error: String(error)}));
    }, error => {
        require('mw-messageservice/MessageService').publish(cfg.channel, {
            token: cfg.token, error: String(error)
        });
    });
    return cfg.token;
})()
