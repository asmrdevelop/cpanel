(function () {
    let path_prefix;
    const scriptTags = document.querySelectorAll('script');
    const currentScript = Array.from(scriptTags).find(
        (script) => script.src.includes('load-scripts-after-zone.js')
    );

    if (currentScript) {
        path_prefix = currentScript.src.split('static/load-scripts-after-zone.js')[0];
    }

    let count = 0;

    function loadScriptsWhenZoneIsAvailable() {
        if (window.Zone) {
            addScript('static/shared-dependencies/long-stack-trace-zone.min.js');
            setTimeout(()=> {
                importScriptMap();
            });
        } else {
            if (count > 5000) {
                count = 0;
                addScript('static/shared-dependencies/zone.min.js');
            }
            setTimeout(loadScriptsWhenZoneIsAvailable, 50);
        }
        count++;
    }

    function importScriptMap() {
        System.addImportMap({imports: {
                '@imunify/other-root': path_prefix + 'static/other-root/main.js',
                '@imunify/email-root': path_prefix + 'static/email-root/main.js',
                '@imunify/nav-root': path_prefix + 'static/nav-root/main.js',
            }});
        addScript('js/config.js');
        addScript('static/index.js');
    }

    function addScript(scriptPath) {
        let script = document.createElement('script');
        script.setAttribute('data-systemjs-only', '1');
        script.setAttribute('src',  path_prefix + scriptPath);
        document.body.appendChild(script);
        return script;
    }

    loadScriptsWhenZoneIsAvailable();
})();
