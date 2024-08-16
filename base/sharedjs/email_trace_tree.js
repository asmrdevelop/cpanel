/*

# cpanel - base/sharedjs/email_trace_tree.js        Copyright 2022 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited
*/
(function() {
    "use strict";

    var LOCALE = window.LOCALE || new CPANEL.Locale();

    var ICON = {
        local: "📥",    // fa-inbox
        remote: "📧",    // fa-paper-plane
        defer: "⏳",    // fa-hourglass
        bounce: "👎",   // fa-thumbs-down
        error: "⛔",    // fa-minus-circle
        command: "⚙️",   // fa-cog
        discard: "🗑️",   // fa-trash

        // Also-ran: ♾️, ⟳
        recursion: "<i class='fa fa-sync-alt' aria-hidden='true'></i>",

        // Also-ran: ⤷, ↰ (rotated), \u2934 (rotated), and ☇ (rotated)
        redirect: LOCALE.is_rtl() ? "↵" : "↳",
    };

    Object.keys(ICON).forEach( function(k) {
        ICON[k] = "<span class='icon-wrapper' aria-hidden='true'>" + ICON[k] + "</span>";
    } );

    function emailTraceTree(node) {
        return _emailTraceTree(node, true);
    }

    // Prioritize failure states:
    var nodeOrder = [
        "error",
        "bounce",
        "local_delivery",
        "remote_delivery",
        "routed",
        "discard",  // sorted last because anything after it is tossed out.
    ];

    function _sortNodes(a, b) {

        // It’s a bit hacky to normalize the recursion here,
        // but we might as well since we’re iterating through
        // the whole branch this way anyway.
        a.recursion = !!(1 * a.recursion);
        b.recursion = !!(1 * b.recursion);

        var aOrder = nodeOrder.indexOf(a.type);
        var bOrder = nodeOrder.indexOf(b.type);

        if (aOrder < bOrder || a.recursion && !b.recursion) {
            return -1;
        } else if (aOrder > bOrder || !a.recursion && b.recursion) {
            return 1;
        }

        return 0;
    }

    function _wrapCode(html) {
        return "<code>" + html + "</code>";
    }

    function _aliasfileHtmlIfNeeded(node) {
        return !node.aliasfile ? "" : "&nbsp;&nbsp;&nbsp;(" + _wrapCode(node.aliasfile.html_encode()) + ")";
    }

    function _emailTraceTree(node, isRoot) {
        var valHtml;

        switch (node.type) {

            case "error":
                valHtml = "<dl><dt>" + ICON.error + LOCALE.maketext("Error") + "</dt>";
                valHtml += "<dd>" + node.result.html_encode() + "</dd>";
                if (node.message) {
                    valHtml += "<dd>" + node.message.html_encode() + "</dd>";
                }
                valHtml += "</dl>";
                break;

            case "local_delivery":
                valHtml = ICON.local + LOCALE.maketext("Delivery: [_1]", _wrapCode(node.mailbox.html_encode()));
                break;

            case "remote_delivery":
                valHtml = "<dl><dt>" + ICON.remote + LOCALE.maketext("Send via [output,abbr,SMTP,Simple Mail Transfer Protocol]") + "</dt>";
                node.mx.forEach( function(mx) {
                    var dd;
                    if (typeof mx === "string") {
                        dd = ICON.defer + _wrapCode(mx.html_encode());
                    } else {
                        dd = "MX: " + _wrapCode(mx.hostname.html_encode()) + " (" + _wrapCode(mx.ip.html_encode()) + ")";

                        if (null !== mx.priority) {
                            dd += ", " + LOCALE.maketext("Priority: [numf,_1]", mx.priority);
                        }
                    }

                    valHtml += "<dd>" + dd + "</dd>";
                } );
                valHtml += "</dl>";
                break;

            case "command":
                valHtml = ICON.command + LOCALE.maketext("Command: “[_1]”", _wrapCode(node.command.html_encode()));

                valHtml += _aliasfileHtmlIfNeeded( node );

                break;

            case "bounce":
                valHtml = ICON.bounce;

                valHtml += node.message ? LOCALE.maketext("Bounce: “[_1]”", node.message.html_encode()) : LOCALE.maketext("Bounce");

                valHtml += _aliasfileHtmlIfNeeded( node );

                break;

            case "discard":
                valHtml = ICON.discard + LOCALE.maketext("Discard");

                valHtml += _aliasfileHtmlIfNeeded( node );

                break;

            case "routed":
                valHtml = _wrapCode( node.address.html_encode() );

                if (!isRoot) {
                    var recursion = 1 * node.recursion;
                    if (recursion) {
                        valHtml = ICON.recursion + LOCALE.maketext("Recursive redirect: [_1]", valHtml);
                    } else {
                        valHtml = ICON.redirect + LOCALE.maketext("Redirect: [_1]", valHtml);
                    }
                }

                valHtml += _aliasfileHtmlIfNeeded( node );

                if (!recursion) {
                    valHtml = "<dl class=\"route-list\"><dt>" + valHtml + "</dt>";
                }

                if (node.destinations) {
                    node.destinations.sort(_sortNodes).forEach( function(subnode) {
                        valHtml += "<dd>" + _emailTraceTree(subnode) + "</dd>";
                    } );
                }

                break;

            default:
                valHtml = JSON.stringify(node).html_encode();
        }

        return valHtml;
    }

    CPANEL.emailTraceTree = emailTraceTree;

}() );
