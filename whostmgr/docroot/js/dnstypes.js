/* eslint-disable */
var dnsload = [];
var fields = {
    "A": [{
        "type": "ipcidr",
        "example": "IPv4 address"
    }],
    "AAAA": [{
        "type": "/^[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}/",
        "example": "IPv6 address"
    }],
    "A6": [{
        "type": "/^[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}:[a-f0-9]{1,4}/",
        "example": "IPv6 address"
    }],
    "AFSDB": [{
        "type": "numeric",
        "example": "numeric subtype"
    }, {
        "type": "host",
        "example": "Hostname"
    }],
    "CAA": [{
        "type": "numeric",
        "example": "flags",
    }, {
        "type": "alphanum",
        "example": "tag"
    }, {
        "type": "host",
        "example": "sslissuer.tld"
    }],
    "CNAME": [{
        "type": "host",
        "example": "Hostname"
    }],
    "DNAME": [{
        "type": "host",
        "example": "Hostname"
    }],
    "DS": [{
        "type": "numeric",
        "example": "Key Tag"
    }, {
        "type": "numeric",
        "example": "Algorithm"
    }, {
        "type": "numeric",
        "example": "Digest Type"
    }, {
        "type": "/^[a-f0-9]+\$/",
        "example": "Digest"
    }],
    "HINFO": [{
        "type": "alphanum",
        "example": '"Hardware Type"'
    }, {
        "type": "alphanum",
        "example": '"OS Version"'
    }],
    "LOC": [{
        "type": "alphanum",
        "example": "Latitude 00 00 00 N"
    }, {
        "type": "alphanum",
        "example": "Longitude 00 00 00 W"
    }, {
        "type": "alphanum",
        "example": "Altitude in Meters 14M"
    }, {
        "type": "alphanum",
        "example": "Horizontal Precision 1000M"
    }, {
        "type": "alphanum",
        "example": "Vertical Precision 1000M"
    }],
    "MX": [{
        "type": "numeric",
        "example": "Priority"
    }, {
        "type": "host",
        "example": "Hostname"
    }],
    "NAPTR": [{
        "type": "numeric",
        "example": "Order"
    }, {
        "type": "numeric",
        "example": "Preferences"
    }, {
        "type": '/^"[^"]*"\$/',
        "example": "Flags"
    }, {
        "type": '/^"[^"]*"\$/',
        "example": "Service"
    }, {
        "type": '/^"[^"]*"\$/',
        "example": "Regex"
    }, {
        "type": "host",
        "example": "Hostname"
    }],
    "NS": [{
        "type": "host",
        "example": "Hostname"
    }],
    "PTR": [{
        "type": "host",
        "example": "Hostname"
    }],
    "RP": [{
        "type": "host",
        "example": "email address with no at sign"
    }, {
        "type": "host",
        "example": "TXT pointer for more info"
    }],
    "SRV": [{
        "type": "numeric",
        "example": "Priority"
    }, {
        "type": "numeric",
        "example": "Weight"
    }, {
        "type": "numeric",
        "example": "Port"
    }, {
        "type": "host",
        "example": "Hostname"
    }],
    "SSHFP": [{
        "type": "numeric",
        "example": "Algorithm"
    }, {
        "type": "numeric",
        "example": "Fingerprint Type"
    }, {
        "type": "/^[a-f0-9]+\$/",
        "example": "Fingerprint"
    }],
    "TXT": [{
        "type": '/^"[^"]*"\$/',
        "example": '"Text Information"'
    }],
    "WKS": [{
        "type": "ipcidr",
        "example": "IP Address"
    }, {
        "type": "alphanum",
        "example": "Protocol"
    }, {
        "type": "/^[A-Za-z\s\(\)]$/",
        "example": "List of Services"
    }

    ]
};

delete fields["SSHFP"]; /* some versions of bind choke here */

function setfields(rowid, recType, nochange) {
    var row;
    var inrow;
    if (rowid.match(/^line/)) {
        var rowinfo = rowid.split(/-/);
        inrow = rowinfo[1];
        row = document.getElementById("current" + inrow);
        if (!row) {
            row = document.getElementById("new" + inrow);
        }
    } else {
        inrow = rowid.replace(/^(current|new)/, "");
        row = document.getElementById(rowid);
    }
    if (nochange) {
        if (typeof (fields[recType]) == "object") {
            var cnt = row.childNodes.length - 4;
            while (cnt > fields[recType].length) {
                cnt--;
                row.removeChild(row.lastChild);
            }
        }
    } else {
        while (row.childNodes.length - 1 > 3) {
            row.removeChild(row.lastChild);
        }
        if (typeof (fields[recType]) == "object") {
            var cnt = row.childNodes.length;
            cnt = cnt - 4;
            var newtd = document.createElement("td");
            newtd.setAttribute("colspan", "2");
            for (i = 0; i < fields[recType].length - cnt; i++) {
                var newcnt = i + 5;
                var newinput = document.createElement("input");
                newinput.setAttribute("name", "line-" + inrow + "-" + newcnt);
                newinput.setAttribute("size", "30");
                newinput.setAttribute("placeholder", fields[recType][i]["example"]);
                newtd.appendChild(newinput);
            }
            row.appendChild(newtd);
        }
    }
    return;
}

function addDnsRow(rowid, recType, nochange) {
    dnsload.push({
        "rowid": rowid,
        "recType": recType,
        "nochange": nochange
    });
}

function processRows() {
    for (var i = 0; i < dnsload.length; i++) {
        setfields(dnsload[i].rowid, dnsload[i].recType, dnsload[i].nochange);
    }
}

if (window.VALIDATIONS) {
    for (var key in VALIDATIONS) {
        VALIDATIONS[key] = new RegExp(VALIDATIONS[key]);
    }
} else {
    VALIDATIONS = {};
}
YAHOO.lang.augmentObject(VALIDATIONS, {
    A: CPANEL.validate.ip,
    AAAA: CPANEL.validate.ipv6
});

function validate_form(the_form) {
    if (window.error_dialog && window.error_dialog.element) {
        window.error_dialog.destroy();
    }

    var cur_el;
    var invalid = [];
    for (var e = 0; cur_el = the_form.elements[e]; e++) {
        var lineMatch = cur_el.name.match(/^line-(\d+)-1$/);
        if (lineMatch && cur_el.value.replace(/\s+/, "")) {
            var type = the_form["line-" + lineMatch[1] + "-4"];
            var record = the_form["line-" + lineMatch[1] + "-1"].value;
            if (type && (type.selectedIndex > -1)) {
                type = type.options[type.selectedIndex].value;
            }
            if (type && (type in VALIDATIONS)) {
                var val = [],
                    i = 5;
                while (cur_el = the_form["line-" + lineMatch[1] + "-" + i]) {
                    if (cur_el.value) {
                        val.push(cur_el.value);
                    }
                    i++;
                }
                val = val.join("\t");

                if (typeof VALIDATIONS[type] === "function") {
                    if (!VALIDATIONS[type](val)) {
                        invalid.push([record, type, val]);
                    }
                } else {
                    if (!VALIDATIONS[type].test(val)) {
                        invalid.push([record, type, val]);
                    }
                }
            }
        }
    }

    if (invalid.length) {
        showerrors(invalid);
        return false;
    }
}

function showerrors(errors) {
    var sd = new CPANEL.ajax.Error_Dialog({
        modal: true,
        fixedcenter: true
    });
    sd.setHeader("<div class='lt'></div><span>" + "Invalid data" + "</span><div class='rt'></div>");
    sd.setBody("<p>The following records are invalid:</p><ul>" + errors.map(function(er) {
        var errorRecord = er[0].html_encode();
        var errorType = er[1].html_encode();
        var errorValue = er[2].length ? er[2].html_encode() : "(empty)";
        return "<li>Record <code>" + errorRecord + "</code> of type <code>" + errorType + "</code>: <code>" + errorValue + "</code></li>";
    }) + "</ul>");

    sd.center();
    sd.show();

    window.error_dialog = sd;
}
/* eslint-enable */
