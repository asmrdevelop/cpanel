(function() {

    var pkgcontainer;
    var pkgreq;

    var PKGS_DATA = {};
    var BOOLEAN_PKG_VALUES = {
        CGI: true,
        HASSHELL: true,
        IP: true
    };
    var PKG_HOVER_TEMPLATE = DOM.get("pkg_hover_template").text.trim();

    var NON_PACKAGES = {
        "---": true,
        "deleted%20account": true,
        "undefined": true
    };

    function loadpkg(o) {
        var pkg;
        try {
            var data = YAHOO.lang.JSON.parse(o.responseText);
            pkg = data.data.pkg;
        } catch (e) {}

        if (pkg) {
            for (var key in pkg) {
                if (pkg[key] === null) {
                    pkg[key] = "\u221e"; // infinity
                } else if (key in BOOLEAN_PKG_VALUES) {
                    pkg[key] = Boolean(Number(pkg[key])) ? LEXICON.yes : LEXICON.no;
                } else {
                    pkg[key] = String(pkg[key]).html_encode();
                }
            }

            PKGS_DATA[o.argument.package] = pkg;
            display_pkg(o.argument.mousetargetEl, o.argument.package);
        }
    }

    var LAST_SHOWN_PACKAGE;

    function display_pkg(mousetargetEl, pkg) {
        if (!pkgcontainer) {
            pkgcontainer = new YAHOO.widget.Panel("pkgpanel", {
                width: "175px",
                fixedcenter: false,
                close: false,
                draggable: false,
                modal: false,
                visible: false
            });
            pkgcontainer.render(document.body);
        }

        if (pkg !== LAST_SHOWN_PACKAGE) {
            if (pkg in PKGS_DATA) {
                pkgcontainer.setBody(YAHOO.lang.substitute(PKG_HOVER_TEMPLATE, PKGS_DATA[pkg]));
            } else {
                pkgcontainer.setBody(LOADING_STRING);
            }

            pkgcontainer.setHeader("<div class='lt'></div><span>" + pkg.html_encode() + "</span><div class='rt'></div>");
        }
    }

    window.hover_pkg = function(mousetargetEl, pkg) {
        if (!pkg && document.mainform && document.mainform.msel) {
            pkg = document.mainform.msel[document.mainform.msel.selectedIndex].text;
        }
        if (!pkg && document.getElementById("pkgselect")) {
            var pkgEl = document.getElementById("pkgselect");
            pkg = pkgEl.options[pkgEl.selectedIndex].text;
        }

        if (!pkg || (pkg in NON_PACKAGES)) {
            return;
        }

        display_pkg(mousetargetEl, pkg);

        pkgcontainer.cfg.setProperty("context", [mousetargetEl, "tl", "br"]);
        pkgcontainer.show();

        if (!PKGS_DATA[pkg]) {
            if (pkgreq) {
                YAHOO.util.Connect.abort(pkgreq);
            }
            var displaycallback = {
                success: loadpkg,
                argument: {
                    "package": pkg,
                    "mousetargetEl": mousetargetEl
                }
            };
            var sUrl = "../json-api/getpkginfo?api.version=1&pkg=" + encodeURIComponent(pkg);
            pkgreq = YAHOO.util.Connect.asyncRequest("GET", sUrl, displaycallback, null);
        }
    };

    window.dehover_pkg = function(mousetargetEl, pkg) {
        if (pkgcontainer) {
            pkgcontainer.hide();
        }
    };

})();
