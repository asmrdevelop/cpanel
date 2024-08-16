/* globals do_quick_popupbox: false */
/* jshint -W098 */
var CONFIRM_DELIP_PANEL = null;

function updateiptbl_code(o) {
    document.getElementById("iplist_master_tbl").innerHTML = o.responseText;
}

function updateiptbl() {
    YAHOO.util.Connect.asyncRequest("POST", CPANEL.security_token + "/scripts2/listips", { success: updateiptbl_code }, "tblonly=1");
}

function process_del_output(result) {
    var parsed;
    var output = "";
    try {
        parsed = JSON.parse(result);
    } catch (e) {}

    if (parsed.delip && parsed.delip.length > 0) {
        if (parsed.delip[0].status) {
            output = parsed.delip[0].statusmsg;
        }
    }

    return output;
}

function delip( ip, iface ) {
    var iface_label;
    if ( null !== iface && "" !== iface ) {
        iface_label = "ethr";
    }
    CONFIRM_DELIP_PANEL.hide();
    do_quick_popupbox( {
        title: "Delete An IP Address",
        url: CPANEL.security_token + "/json-api/delip?ip=" + ip + "&ethernetdev=" + iface + "&skip_if_shutdown=0",
        callback: updateiptbl,
        showloading: 1,
        processOutput: process_del_output
    }, "ip", ip, iface_label, iface );
}

function confirm_delip( ip, iface) {
    if (!CONFIRM_DELIP_PANEL) {
        var panel_options = {
            width: "500px",
            fixedcenter: true,
            close: true,
            draggable: false,
            modal: true,
            visible: true
        };
        CONFIRM_DELIP_PANEL = new YAHOO.widget.Panel("confirmDeletePanel", panel_options);
        CONFIRM_DELIP_PANEL.render();
        YAHOO.util.Event.addListener("cancelRemoveBtn", "click", function() {
            CONFIRM_DELIP_PANEL.hide();
        });
    }

    document.getElementById("confirmDeleteBody").innerHTML = LOCALE.maketext("Are you sure you wish to remove “[_1]”?", ip);
    YAHOO.util.Event.removeListener("confirmRemoveBtn", "click");
    YAHOO.util.Event.addListener("confirmRemoveBtn", "click", function() {
        delip(ip, iface);
    });
    CONFIRM_DELIP_PANEL.show();
}
