var jsonLangCacheRef;
var didcheckeditlang = 0;

function refreshlang(o) {
    var jsonRef = (o.argument.json ? o.argument.json : YAHOO.lang.JSON.parse(o.responseText));
    jsonLangCacheRef = jsonRef;
    var neededlang = o.argument.lang;
    var showall = o.argument.showall;
    var langEl = o.argument.langEl;
    var langSubmit = o.argument.langSubmit;
    var themes = jsonRef["themes"];
    var El = document.getElementById(o.argument.elid);
    for (var i = 0; i < El.options.length; i++) {
        El.options[i] = null;
    }
    El.options.length = 0;
    if (showall > 0) {
        El.options[El.options.length] = new Option("Root, Addons & All Themes", "__ALL__");
    }
    for (var name in themes) {
        if (themes[name][neededlang]) {
            var icount = El.options.length;
            if (name == "/") {
                if (showall == -1) {
                    continue;
                }
                El.options[icount] = new Option("Root Language File", "/");
            } else {
                El.options[icount] = new Option(name, name);
            }
        }
    }
    langEl.disabled = false;
    El.disabled = false;
    document.getElementById(langSubmit).disabled = false;

    if (typeof (window["checkeditlang"]) != "undefined" && !didcheckeditlang) {
        didcheckeditlang = 1;
        checkeditlang();

    }
}
