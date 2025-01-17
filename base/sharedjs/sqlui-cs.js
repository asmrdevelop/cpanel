//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/sqlui.js
// Generated: /usr/local/cpanel/base/sharedjs/sqlui-cs.js
// Module:    legacy_shared/sqlui-cs
// Locale:    cs
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Close":"Zavřít","If you change this database’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"Jestliže změníte název této databáze, nebudete moci ji přejmenovat zpět na „[_1]“. Je to kvůli tomu, že ve starém názvu chybí předpona jména uživatele ([_2]), kterou tento systém vyžaduje pro názvy všech nových databází a uživatelů databází. Pokud požadujete název bez předpony, musíte kontaktovat administrátora serveru.","If you change this user’s name, you will be unable to rename it back to “[_1]”. This is because the old name lacks the username prefix ([_2]) that this system requires on the names of all new databases and database users. If you require a name without the prefix, you must contact your server administrator.":"Jestliže změníte jméno tohoto uživatele, nebudete moci jej přejmenovat zpět na „[_1]“. Je to kvůli tomu, že ve starém názvu chybí předpona jména uživatele ([_2]), kterou tento systém vyžaduje pro názvy všech nových databází a uživatelů databází. Pokud požadujete název bez předpony, musíte kontaktovat administrátora serveru.","It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.":"It is a potentially dangerous operation to rename a database. You may want to [output,url,_1,back up this database] before renaming it.","Rename Database":"Přejmenovat databázi","Rename Database User":"Přejmenovat uživatele databáze","Renaming database user …":"Přejmenování uživatele databáze…","Renaming database …":"Přejmenování databáze…","Success! The browser is now redirecting …":"Úspěch! Probíhá přesměrování prohlížeče…","Success! This page will now reload.":"Úspěch! Tato stránka se nyní znovu načte.","The new name must be different from the old name.":"Nový název se musí lišit od starého názvu."};

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
