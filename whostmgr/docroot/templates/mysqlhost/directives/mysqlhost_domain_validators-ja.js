//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/mysqlhost/directives/mysqlhost_domain_validators.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/mysqlhost/directives/mysqlhost_domain_validators-ja.js
// Module:    /templates/mysqlhost/directives/mysqlhost_domain_validators-ja
// Locale:    ja
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The host must be a valid [asis,IP] address or [asis,hostname].":"ホストは、有効な[asis,IP]アドレスまたは[asis,hostname]でなければなりません。","The value must be a valid [asis,loopback] address.":"値は有効な[asis,loopback]アドレスである必要があります。"};

    if (!this.LEXICON) {
        this.LEXICON = {};
    }

    for(var item in newLex) {
        if(newLex.hasOwnProperty(item)) {
            var value = newLex[item];
            if (typeof(value) === "string" && value !== "") {
                // Only add it if there is a value.
                this.LEXICON[item] = value;
            }
        }
    }
})();
//~~END-GENERATED~~
