//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/hulkd/views/configController.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/hulkd/views/configController-da.js
// Module:    /templates/hulkd/views/configController-da
// Locale:    da
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The system disabled the [asis,UseDNS] setting for [asis,SSHD] in order to add IP addresses to the whitelist. You must restart SSH through the [output,url,_1,Restart SSH Server,_2] page to implement the change.":"Systemet deaktiverede [asis,UseDNS]-indstillingen for [asis,SSHD] for at kunne føje IP-adresser til godkendt-listen. Du skal genstarte SSH via siden [output,url,_1,Genstart SSH-server,_2] for at implementere ændringen.","The system successfully saved your [asis,cPHulk] configuration settings.":"Systemet har gemt dine [asis,cPHulk]-konfigurationsindstillinger.","You changed the protection level of [asis,cPHulk]. Click Save to implement this change.":"You changed the protection level of [asis,cPHulk]. Click Save to implement this change."};

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