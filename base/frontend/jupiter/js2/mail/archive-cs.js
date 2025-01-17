//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/frontend/jupiter/js2/mail/archive.js
// Generated: /usr/local/cpanel/base/frontend/jupiter/js2/mail/archive-cs.js
// Module:    /jupiter/js2/mail/archive-cs
// Locale:    cs
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"AJAX Error":"Chyba AJAX","An archive retention period of “[_1]” is not valid.":"Doba uchování archivu „[_1]“ není platná.","Applied the default email archive configuration to all the domains on this account.":"Výchozí konfigurace archivace pošty byla použita na všechny domény v tomto účtu.","Applied to [numf,_1] of [quant,_2,domain,domains].":"Použito pro [numf,_1] z [quant,_2,domény,domén].","Archive Download Selection":"Výběr stažení archivu","Are you sure you want to disable archiving of incoming email for “[_1]”?":"Opravdu chcete zakázat archivaci příchozích e-mailů pro „[_1]“?","Are you sure you want to disable archiving of mailing lists for “[_1]”?":"Opravdu chcete zakázat archivaci distribučních seznamů pro „[_1]“?","Are you sure you want to disable archiving of outgoing email for “[_1]”?":"Opravdu chcete zakázat archivaci odchozích e-mailů pro „[_1]“?","Are you sure you want to disable archiving of “[_1]” email for “[_2]”?":"Opravdu chcete zakázat archivaci e-mailu „[_1]“ pro „[_2]“?","Close":"Zavřít","Currently processing domain # [numf,_1] of [numf,_2].":"Právě probíhá zpracování domény číslo [numf,_1] z [numf,_2].","Disabled archiving of incoming email for all new domains.":"Zakázána archivace příchozích e-mailů pro všechny nové domény.","Disabled archiving of incoming mail for “[_1]”.":"Zakázána archivace příchozí pošty pro „[_1]“.","Disabled archiving of mailing lists for all new domains.":"Zakázána archivace distribučních seznamů pro všechny nové domény.","Disabled archiving of mailing lists for “[_1]”.":"Zakázáno archivování distribučních seznamů pro „[_1]“.","Disabled archiving of outgoing email for all new domains.":"Zakázaná archivace odchozích e-mailů pro všechny nové domény.","Disabled archiving of outgoing email for “[_1]”.":"Zakázána archivace odchozích e-mailů pro „[_1]“.","Disabled archiving of “[_1]” email for “[_2]”.":"Zakázána archivace e-mailů „[_1]“ pro „[_2]“.","Disabled archiving of “[_1]” for all new domains.":"Zakázaná archivace „[_1]“ pro všechny nové domény.","Enabled archiving of incoming email for all new domains.":"Povolena archivace příchozích e-mailů pro všechny nové domény.","Enabled archiving of incoming email on “[_1]”.":"Povolena archivace příchozích e-mailů pro „[_1]“.","Enabled archiving of mailing lists for all new domains.":"Povolena archivace distribučních seznamů pro všechny nové domény.","Enabled archiving of mailing lists on “[_1]”.":"Povolena archivace distribučních seznamů na adrese „[_1]“.","Enabled archiving of outgoing email for all new domains.":"Povolena archivace odchozích e-mailů pro všechny nové domény.","Enabled archiving of outgoing email on “[_1]”.":"Povolena archivace odchozích e-mailů pro „[_1]“.","Enabled archiving of “[_1]” email for all new domains.":"Povolena archivace e-mailů „[_1]“ pro všechny nové domény.","Enabled archiving of “[_1]” email on “[_2]”.":"Povolena archivace e-mailu „[_1]“ ve složce „[_2]“.","Error":"Chyba","Please refresh the page and try again.":"Obnovte stránku a zkuste to znovu.","The archive retention period of “[_1]” email for all new domains is now Forever.":"Doba uchování archivu e-mailů „[_1]“ pro všechny nové domény je aktuálně Navždy.","The archive retention period of “[_1]” email for all new domains is now [quant,_2,day,days].":"Doba uchování archivu e-mailů „[_1]“ pro všechny nové domény je aktuálně [quant,_2,den,dny/dnů].","The archive retention period of “[_1]” email for all new domains is now “[_2]”.":"Doba uchování archivu e-mailů „[_1]“ pro všechny nové domény je aktuálně „[_2]“.","The archive retention period of “[_1]” email for “[_2]” is now Forever.":"Doba uchování archivu e-mailu „[_1]“ pro „[_2]“ je nyní Navždy.","The archive retention period of “[_1]” email for “[_2]” is now [quant,_3,day,days].":"Doba uchování e-mailového archivu „[_1]“ pro „[_2]“ je aktuálně [quant,_3,den,dny/dnů].","The archive retention period of “[_1]” email for “[_2]” is now “[_3]”.":"Doba uchování e-mailového archivu „[_1]“ pro „[_2]“ je aktuálně [_3].","The archive retention period of “[_1]” for all new domains is now Forever.":"Doba uchování archivu „[_1]“ pro všechny nové domény je aktuálně Navždy.","The archive retention period of “[_1]” for all new domains is now [quant,_2,day,days].":"Doba uchování archivu e-mailů „[_1]“ pro všechny nové domény je aktuálně [quant,_2,den,dny/dnů].","The archive retention period of “[_1]” for “[_2]” is now Forever.":"Doba uchování archivu „[_1]“ pro „[_2]“ je nyní Navždy.","The archive retention period of “[_1]” for “[_2]” is now [quant,_3,day,days].":"Doba uchování archivu „[_1]“ pro „[_2]“ je nyní [quant,_3,den,dny/dnů].","The archive retention period of “[_1]” for “[_2]” is now “[_3]”.":"Doba uchování archivu „[_1]“ pro „[_2]“ je nyní „[_3]“.","You have unsaved changes.":"Existují neuložené změny."};

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
